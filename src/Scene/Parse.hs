module Scene.Parse
  ( parse,
    parseCachedStmtList,
  )
where

import Context.Alias qualified as Alias
import Context.App
import Context.Cache qualified as Cache
import Context.Env qualified as Env
import Context.Gensym qualified as Gensym
import Context.Global qualified as Global
import Context.Locator qualified as Locator
import Context.Throw qualified as Throw
import Context.UnusedVariable qualified as UnusedVariable
import Control.Comonad.Cofree hiding (section)
import Control.Monad
import Control.Monad.Trans
import Data.Maybe
import Data.Text qualified as T
import Data.Vector qualified as V
import Entity.ArgNum qualified as AN
import Entity.BaseName qualified as BN
import Entity.Cache qualified as Cache
import Entity.Const
import Entity.DefiniteDescription qualified as DD
import Entity.Discriminant qualified as D
import Entity.GlobalName qualified as GN
import Entity.Hint
import Entity.Ident.Reify
import Entity.IsConstLike
import Entity.Name
import Entity.NameArrow qualified as NA
import Entity.Opacity qualified as O
import Entity.RawBinder
import Entity.RawPattern qualified as RP
import Entity.RawTerm qualified as RT
import Entity.Source qualified as Source
import Entity.Stmt
import Entity.StmtKind qualified as SK
import Path
import Scene.Parse.Core qualified as P
import Scene.Parse.Discern qualified as Discern
import Scene.Parse.Export qualified as Parse
import Scene.Parse.Import qualified as Parse
import Scene.Parse.RawTerm
import Text.Megaparsec hiding (parse)

--
-- core functions
--

parse :: App (Either Cache.Cache ([WeakStmt], [NA.NameArrow]))
parse = do
  source <- Env.getCurrentSource
  result <- parseSource source
  mMainDD <- Locator.getMainDefiniteDescription source
  case mMainDD of
    Just mainDD -> do
      let m = Entity.Hint.new 1 1 $ toFilePath $ Source.sourceFilePath source
      ensureMain m mainDD
      return result
    Nothing ->
      return result

parseSource :: Source.Source -> App (Either Cache.Cache ([WeakStmt], [NA.NameArrow]))
parseSource source = do
  mCache <- Cache.loadCache source
  let path = Source.sourceFilePath source
  case mCache of
    Just cache -> do
      let stmtList = Cache.stmtList cache
      parseCachedStmtList stmtList
      mapM_ Global.registerStmtExport $ Cache.nameArrowList cache
      Global.saveCurrentNameSet path $ Cache.nameArrowList cache
      return $ Left cache
    Nothing -> do
      (defList, nameArrowList) <- P.run (program source) $ Source.sourceFilePath source
      registerTopLevelNames defList
      stmtList <- Discern.discernStmtList defList
      nameArrowList' <- concat <$> mapM Discern.discernNameArrow nameArrowList
      mapM_ Global.registerStmtExport nameArrowList'
      Global.saveCurrentNameSet path nameArrowList'
      UnusedVariable.registerRemarks
      return $ Right (stmtList, nameArrowList')

parseCachedStmtList :: [Stmt] -> App ()
parseCachedStmtList stmtList = do
  forM_ stmtList $ \stmt -> do
    case stmt of
      StmtDefine isConstLike stmtKind m name impArgNum args _ _ -> do
        let explicitArgs = drop (AN.reify impArgNum) args
        let argNames = map (\(_, x, _) -> toText x) explicitArgs
        Global.registerStmtDefine isConstLike m stmtKind name impArgNum argNames
      StmtDefineResource m name _ _ ->
        Global.registerStmtDefineResource m name

ensureMain :: Hint -> DD.DefiniteDescription -> App ()
ensureMain m mainFunctionName = do
  mMain <- Global.lookup m mainFunctionName
  case mMain of
    Just (GN.TopLevelFunc _ _) ->
      return ()
    _ ->
      Throw.raiseError m "`main` is missing"

program :: Source.Source -> P.Parser ([RawStmt], [NA.RawNameArrow])
program currentSource = do
  m <- P.getCurrentHint
  sourceInfoList <- Parse.parseImportBlock currentSource
  nameArrowList <- Parse.parseExportBlock
  forM_ sourceInfoList $ \(source, aliasInfo) -> do
    lift $ Global.activateTopLevelNamesInSource m source
    lift $ Alias.activateAliasInfo aliasInfo
  defList <- concat <$> many parseStmt <* eof
  return (defList, nameArrowList)

parseStmt :: P.Parser [RawStmt]
parseStmt = do
  choice
    [ parseDefineVariant,
      parseDefineStruct,
      return <$> parseAliasOpaque,
      return <$> parseAliasTransparent,
      return <$> parseDefineResource,
      return <$> parseDefine O.Transparent,
      return <$> parseDefine O.Opaque
    ]

--
-- parser for statements
--

-- define name (x1 : A1) ... (xn : An) : A = e
parseDefine :: O.Opacity -> P.Parser RawStmt
parseDefine opacity = do
  try $
    case opacity of
      O.Opaque ->
        P.keyword "define"
      O.Transparent ->
        P.keyword "define-inline"
  m <- P.getCurrentHint
  ((_, name), impArgs, expArgs, codType, e) <- parseTopDefInfo
  name' <- lift $ Locator.attachCurrentLocator name
  lift $ defineFunction (SK.Normal opacity) m name' (AN.fromInt $ length impArgs) (impArgs ++ expArgs) codType e

defineFunction ::
  SK.RawStmtKind ->
  Hint ->
  DD.DefiniteDescription ->
  AN.ArgNum ->
  [RawBinder RT.RawTerm] ->
  RT.RawTerm ->
  RT.RawTerm ->
  App RawStmt
defineFunction stmtKind m name impArgNum binder codType e = do
  return $ RawStmtDefine False stmtKind m name impArgNum binder codType e

parseDefineVariant :: P.Parser [RawStmt]
parseDefineVariant = do
  m <- P.getCurrentHint
  try $ P.keyword "variant"
  a <- P.baseName >>= lift . Locator.attachCurrentLocator
  dataArgsOrNone <- parseDataArgs
  consInfoList <- P.betweenBrace $ P.manyList parseDefineVariantClause
  lift $ defineData m a dataArgsOrNone consInfoList []

parseDataArgs :: P.Parser (Maybe [RawBinder RT.RawTerm])
parseDataArgs = do
  choice
    [ Just <$> P.argList preBinder,
      return Nothing
    ]

defineData ::
  Hint ->
  DD.DefiniteDescription ->
  Maybe [RawBinder RT.RawTerm] ->
  [(Hint, BN.BaseName, IsConstLike, [RawBinder RT.RawTerm])] ->
  [DD.DefiniteDescription] ->
  App [RawStmt]
defineData m dataName dataArgsOrNone consInfoList projectionList = do
  let dataArgs = fromMaybe [] dataArgsOrNone
  consInfoList' <- mapM modifyConstructorName consInfoList
  let consInfoList'' = modifyConsInfo D.zero consInfoList'
  let stmtKind = SK.Data dataName dataArgs consInfoList'' projectionList
  let consNameList = map (\(consName, _, _, _) -> consName) consInfoList''
  let dataType = constructDataType m dataName consNameList dataArgs
  let isConstLike = isNothing dataArgsOrNone
  let formRule = RawStmtDefine isConstLike stmtKind m dataName (AN.fromInt 0) dataArgs (m :< RT.Tau) dataType
  introRuleList <- parseDefineVariantConstructor dataType dataName dataArgs consInfoList' D.zero
  return $ formRule : introRuleList

modifyConsInfo ::
  D.Discriminant ->
  [(a, DD.DefiniteDescription, b, [RawBinder RT.RawTerm])] ->
  [(DD.DefiniteDescription, b, [RawBinder RT.RawTerm], D.Discriminant)]
modifyConsInfo d consInfoList =
  case consInfoList of
    [] ->
      []
    (_, consName, isConstLike, consArgs) : rest ->
      (consName, isConstLike, consArgs, d) : modifyConsInfo (D.increment d) rest

modifyConstructorName ::
  (Hint, BN.BaseName, IsConstLike, [RawBinder RT.RawTerm]) ->
  App (Hint, DD.DefiniteDescription, IsConstLike, [RawBinder RT.RawTerm])
modifyConstructorName (mb, consName, isConstLike, yts) = do
  consName' <- Locator.attachCurrentLocator consName
  return (mb, consName', isConstLike, yts)

parseDefineVariantConstructor ::
  RT.RawTerm ->
  DD.DefiniteDescription ->
  [RawBinder RT.RawTerm] ->
  [(Hint, DD.DefiniteDescription, IsConstLike, [RawBinder RT.RawTerm])] ->
  D.Discriminant ->
  App [RawStmt]
parseDefineVariantConstructor dataType dataName dataArgs consInfoList discriminant = do
  case consInfoList of
    [] ->
      return []
    (m, consName, isConstLike, consArgs) : rest -> do
      let dataArgs' = map identPlusToVar dataArgs
      let consArgs' = map identPlusToVar consArgs
      let consNameList = map (\(_, c, _, _) -> c) consInfoList
      let args = dataArgs ++ consArgs
      let introRule =
            RawStmtDefine
              isConstLike
              (SK.DataIntro consName dataArgs consArgs discriminant)
              m
              consName
              (AN.fromInt $ length dataArgs)
              args
              dataType
              $ m :< RT.DataIntro dataName consName consNameList discriminant dataArgs' consArgs'
      introRuleList <- parseDefineVariantConstructor dataType dataName dataArgs rest (D.increment discriminant)
      return $ introRule : introRuleList

constructDataType ::
  Hint ->
  DD.DefiniteDescription ->
  [DD.DefiniteDescription] ->
  [RawBinder RT.RawTerm] ->
  RT.RawTerm
constructDataType m dataName consNameList dataArgs = do
  m :< RT.Data dataName consNameList (map identPlusToVar dataArgs)

parseDefineVariantClause :: P.Parser (Hint, BN.BaseName, IsConstLike, [RawBinder RT.RawTerm])
parseDefineVariantClause = do
  m <- P.getCurrentHint
  consName <- P.baseNameCapitalized
  consArgsOrNone <- parseConsArgs
  let consArgs = fromMaybe [] consArgsOrNone
  let isConstLike = isNothing consArgsOrNone
  return (m, consName, isConstLike, consArgs)

parseConsArgs :: P.Parser (Maybe [RawBinder RT.RawTerm])
parseConsArgs = do
  choice
    [ Just <$> P.argList parseDefineVariantClauseArg,
      return Nothing
    ]

parseDefineVariantClauseArg :: P.Parser (RawBinder RT.RawTerm)
parseDefineVariantClauseArg = do
  choice
    [ try preAscription,
      typeWithoutIdent
    ]

parseDefineStruct :: P.Parser [RawStmt]
parseDefineStruct = do
  m <- P.getCurrentHint
  try $ P.keyword "struct"
  dataName <- P.baseName >>= lift . Locator.attachCurrentLocator
  dataArgsOrNone <- parseDataArgs
  P.keyword "by"
  consName <- P.baseNameCapitalized
  elemInfoList <- P.betweenBrace $ P.manyList preAscription
  let dataArgs = fromMaybe [] dataArgsOrNone
  consName' <- lift $ Locator.attachCurrentLocator consName
  let structElimHandler = parseDefineStructElim dataName dataArgs consName' elemInfoList
  (elimRuleList, projList) <- mapAndUnzipM (lift . structElimHandler) elemInfoList
  formRule <- lift $ defineData m dataName dataArgsOrNone [(m, consName, False, elemInfoList)] projList
  return $ formRule ++ elimRuleList

-- noetic projection
parseDefineStructElim ::
  DD.DefiniteDescription ->
  [RawBinder RT.RawTerm] ->
  DD.DefiniteDescription ->
  [RawBinder RT.RawTerm] ->
  RawBinder RT.RawTerm ->
  App (RawStmt, DD.DefiniteDescription)
parseDefineStructElim dataName dataArgs consName elemInfoList (m, elemName, elemType) = do
  let structType = m :< RT.Noema (constructDataType m dataName [consName] dataArgs)
  structVarText <- Gensym.newText
  let projArgs = dataArgs ++ [(m, structVarText, structType)]
  elemName' <- Throw.liftEither $ BN.reflect m elemName
  projectionName <- Locator.attachCurrentLocator elemName'
  let argList = flip map elemInfoList $ \(mx, x, _) -> (mx, RP.Var (Var $ holeVarPrefix <> x))
  stmt <-
    defineFunction
      -- (Normal O.Opaque)
      SK.Projection
      m
      projectionName -- e.g. some-lib.foo::my-struct.element-x
      (AN.fromInt $ length dataArgs)
      projArgs
      (m :< RT.Noema elemType)
      $ m
        :< RT.DataElim
          True
          [preVar m structVarText]
          ( RP.new
              [ ( V.fromList [(m, RP.Cons (DefiniteDescription consName) argList)],
                  preVar m (holeVarPrefix <> elemName)
                )
              ]
          )
  return (stmt, projectionName)

parseAliasTransparent :: P.Parser RawStmt
parseAliasTransparent = do
  parseType "alias" O.Transparent

parseAliasOpaque :: P.Parser RawStmt
parseAliasOpaque = do
  parseType "alias-opaque" O.Opaque

parseType :: T.Text -> O.Opacity -> P.Parser RawStmt
parseType keywordText opacity = do
  m <- P.getCurrentHint
  try $ P.keyword keywordText
  aliasName <- P.baseName
  aliasName' <- lift $ Locator.attachCurrentLocator aliasName
  P.betweenBrace $ do
    t <- rawExpr
    let stmtKind = SK.Normal opacity
    return $ RawStmtDefine True stmtKind m aliasName' AN.zero [] (m :< RT.Tau) t

parseDefineResource :: P.Parser RawStmt
parseDefineResource = do
  try $ P.keyword "resource"
  m <- P.getCurrentHint
  name <- P.baseName
  name' <- lift $ Locator.attachCurrentLocator name
  P.betweenBrace $ do
    discarder <- P.delimiter "-" >> rawExpr
    copier <- P.delimiter "-" >> rawExpr
    return $ RawStmtDefineResource m name' discarder copier

identPlusToVar :: RawBinder RT.RawTerm -> RT.RawTerm
identPlusToVar (m, x, _) =
  m :< RT.Var (Var x)

registerTopLevelNames :: [RawStmt] -> App ()
registerTopLevelNames stmtList =
  case stmtList of
    [] ->
      return ()
    RawStmtDefine isConstLike stmtKind m functionName impArgNum xts _ _ : rest -> do
      let explicitArgs = drop (AN.reify impArgNum) xts
      let argNames = map (\(_, x, _) -> x) explicitArgs
      Global.registerStmtDefine isConstLike m stmtKind functionName impArgNum argNames
      registerTopLevelNames rest
    RawStmtDefineResource m name _ _ : rest -> do
      Global.registerStmtDefineResource m name
      registerTopLevelNames rest
