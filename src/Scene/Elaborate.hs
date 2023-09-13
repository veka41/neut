module Scene.Elaborate (elaborate) where

import Context.App
import Context.Cache qualified as Cache
import Context.DataDefinition qualified as DataDefinition
import Context.Definition qualified as Definition
import Context.Elaborate
import Context.Env qualified as Env
import Context.Locator qualified as Locator
import Context.NameDependence qualified as NameDependence
import Context.Remark qualified as Remark
import Context.Throw qualified as Throw
import Context.Type qualified as Type
import Context.Via qualified as Via
import Context.WeakDefinition qualified as WeakDefinition
import Control.Comonad.Cofree
import Control.Monad
import Data.HashMap.Strict qualified as Map
import Data.IntMap qualified as IntMap
import Data.List
import Data.Set qualified as S
import Data.Text qualified as T
import Entity.Annotation qualified as AN
import Entity.Binder
import Entity.Cache qualified as Cache
import Entity.DecisionTree qualified as DT
import Entity.Decl qualified as DE
import Entity.DefiniteDescription qualified as DD
import Entity.ExternalName qualified as EN
import Entity.Hint
import Entity.HoleID qualified as HID
import Entity.HoleSubst qualified as HS
import Entity.Ident.Reify qualified as Ident
import Entity.LamKind qualified as LK
import Entity.Macro (MacroInfo)
import Entity.Magic qualified as M
import Entity.Prim qualified as P
import Entity.PrimType qualified as PT
import Entity.PrimValue qualified as PV
import Entity.Remark qualified as Remark
import Entity.Source qualified as Source
import Entity.Stmt
import Entity.StmtKind
import Entity.Term qualified as TM
import Entity.Term.Weaken
import Entity.ViaMap qualified as VM
import Entity.WeakPrim qualified as WP
import Entity.WeakPrimValue qualified as WPV
import Entity.WeakTerm qualified as WT
import Entity.WeakTerm.ToText
import Scene.Elaborate.Infer qualified as Infer
import Scene.Elaborate.Reveal qualified as Reveal
import Scene.Elaborate.Unify qualified as Unify
import Scene.Term.Reduce qualified as Term
import Scene.WeakTerm.Reduce qualified as WT
import Scene.WeakTerm.Subst qualified as WT

elaborate :: Either Cache.Cache ([WeakStmt], [MacroInfo], [DE.Decl]) -> App ([Stmt], [DE.Decl])
elaborate cacheOrStmt = do
  initialize
  case cacheOrStmt of
    Left cache -> do
      let stmtList = Cache.stmtList cache
      forM_ stmtList insertStmt
      let remarkList = Cache.remarkList cache
      Remark.insertToGlobalRemarkList remarkList
      Remark.printRemarkList remarkList
      let declList = Cache.declList cache
      return (stmtList, declList)
    Right (defList, macroInfo, declList) -> do
      defList' <- (analyzeDefList >=> synthesizeDefList macroInfo declList) defList
      return (defList', declList)

analyzeDefList :: [WeakStmt] -> App [WeakStmt]
analyzeDefList defList = do
  defList' <- forM defList $ \stmt -> do
    stmt' <- Reveal.revealStmt stmt
    insertWeakStmt stmt'
    return stmt'
  source <- Env.getCurrentSource
  mMainDD <- Locator.getMainDefiniteDescription source
  mapM (Infer.inferStmt mMainDD) defList'

-- viewStmt :: WeakStmt -> App ()
-- viewStmt stmt = do
--   case stmt of
--     WeakStmtDefine _ _ m x _ xts codType e ->
--       Remark.printNote m $ DD.reify x <> "\n" <> toText (m :< WT.Pi xts codType) <> "\n" <> toText (m :< WT.PiIntro (LK.Normal O.Transparent) xts e)
--     WeakStmtDefineResource m name discarder copier ->
--       Remark.printNote m $ "define-resource" <> DD.reify name <> "\n" <> toText discarder <> toText copier

synthesizeDefList :: [MacroInfo] -> [DE.Decl] -> [WeakStmt] -> App [Stmt]
synthesizeDefList macroInfoList declList defList = do
  -- mapM_ viewStmt defList
  getConstraintEnv >>= Unify.unify >>= setHoleSubst
  defList' <- mapM elaborateStmt defList
  -- mapM_ (viewStmt . weakenStmt) defList'
  source <- Env.getCurrentSource
  remarkList <- Remark.getRemarkList
  tmap <- Env.getTagMap
  let path = Source.sourceFilePath source
  nameDependence <- NameDependence.get path
  viaInfo <- Via.get path
  Cache.saveCache source $
    Cache.Cache
      { Cache.stmtList = defList',
        Cache.remarkList = remarkList,
        Cache.locationTree = tmap,
        Cache.declList = declList,
        Cache.macroInfoList = macroInfoList,
        Cache.nameDependence = Map.toList nameDependence,
        Cache.viaInfo = VM.encode viaInfo
      }
  Remark.printRemarkList remarkList
  Remark.insertToGlobalRemarkList remarkList
  return defList'

elaborateStmt :: WeakStmt -> App Stmt
elaborateStmt stmt = do
  case stmt of
    WeakStmtDefine isConstLike stmtKind m x impArgNum xts codType e -> do
      stmtKind' <- elaborateStmtKind stmtKind
      e' <- elaborate' e >>= Term.reduce
      xts' <- mapM elaborateWeakBinder xts
      codType' <- elaborate' codType >>= Term.reduce
      Type.insert x $ weaken $ m :< TM.Pi xts' codType'
      let result = StmtDefine isConstLike stmtKind' m x impArgNum xts' codType' e'
      insertStmt result
      return result
    WeakStmtDefineResource m name discarder copier -> do
      discarder' <- elaborate' discarder
      copier' <- elaborate' copier
      let result = StmtDefineResource m name discarder' copier'
      insertStmt result
      return result

insertStmt :: Stmt -> App ()
insertStmt stmt = do
  case stmt of
    StmtDefine _ stmtKind _ f _ xts _ e -> do
      Definition.insert (toOpacity stmtKind) f xts e
    StmtDefineResource {} ->
      return ()
  insertWeakStmt $ weakenStmt stmt
  insertStmtKindInfo stmt

insertWeakStmt :: WeakStmt -> App ()
insertWeakStmt stmt = do
  case stmt of
    WeakStmtDefine _ stmtKind m f _ xts codType e -> do
      Type.insert f $ m :< WT.Pi xts codType
      WeakDefinition.insert (toOpacity stmtKind) m f xts e
    WeakStmtDefineResource m name _ _ ->
      Type.insert name $ m :< WT.Tau

insertStmtKindInfo :: Stmt -> App ()
insertStmtKindInfo stmt = do
  case stmt of
    StmtDefine _ stmtKind _ _ _ _ _ _ -> do
      case stmtKind of
        Normal _ ->
          return ()
        Data dataName dataArgs consInfoList -> do
          DataDefinition.insert dataName dataArgs consInfoList
        DataIntro {} ->
          return ()
    StmtDefineResource {} ->
      return ()

elaborateStmtKind :: StmtKind WT.WeakTerm -> App (StmtKind TM.Term)
elaborateStmtKind stmtKind =
  case stmtKind of
    Normal opacity ->
      return $ Normal opacity
    Data dataName dataArgs consInfoList -> do
      dataArgs' <- mapM elaborateWeakBinder dataArgs
      let (ms, consNameList, constLikeList, consArgsList, discriminantList) = unzip5 consInfoList
      consArgsList' <- mapM (mapM elaborateWeakBinder) consArgsList
      let consInfoList' = zip5 ms consNameList constLikeList consArgsList' discriminantList
      return $ Data dataName dataArgs' consInfoList'
    DataIntro dataName dataArgs consArgs discriminant -> do
      dataArgs' <- mapM elaborateWeakBinder dataArgs
      consArgs' <- mapM elaborateWeakBinder consArgs
      return $ DataIntro dataName dataArgs' consArgs' discriminant

elaborate' :: WT.WeakTerm -> App TM.Term
elaborate' term =
  case term of
    m :< WT.Tau ->
      return $ m :< TM.Tau
    m :< WT.Var x ->
      return $ m :< TM.Var x
    m :< WT.VarGlobal name argNum ->
      return $ m :< TM.VarGlobal name argNum
    m :< WT.Pi xts t -> do
      xts' <- mapM elaborateWeakBinder xts
      t' <- elaborate' t
      return $ m :< TM.Pi xts' t'
    m :< WT.PiIntro kind xts e -> do
      kind' <- elaborateKind kind
      xts' <- mapM elaborateWeakBinder xts
      e' <- elaborate' e
      return $ m :< TM.PiIntro kind' xts' e'
    m :< WT.PiElim e es -> do
      e' <- elaborate' e
      es' <- mapM elaborate' es
      return $ m :< TM.PiElim e' es'
    m :< WT.Data name consNameList es -> do
      es' <- mapM elaborate' es
      return $ m :< TM.Data name consNameList es'
    m :< WT.DataIntro dataName consName consNameList disc dataArgs consArgs -> do
      dataArgs' <- mapM elaborate' dataArgs
      consArgs' <- mapM elaborate' consArgs
      return $ m :< TM.DataIntro dataName consName consNameList disc dataArgs' consArgs'
    m :< WT.DataElim isNoetic oets tree -> do
      let (os, es, ts) = unzip3 oets
      es' <- mapM elaborate' es
      ts' <- mapM elaborate' ts
      tree' <- elaborateDecisionTree m tree
      when (DT.isUnreachable tree') $ do
        forM_ ts' $ \t -> do
          t' <- reduceType (weaken t)
          consList <- extractConstructorList m t'
          unless (null consList) $
            raiseNonExhaustivePatternMatching m
      return $ m :< TM.DataElim isNoetic (zip3 os es' ts') tree'
    m :< WT.Noema t -> do
      t' <- elaborate' t
      return $ m :< TM.Noema t'
    m :< WT.Embody t e -> do
      t' <- elaborate' t
      e' <- elaborate' e
      return $ m :< TM.Embody t' e'
    m :< WT.Let opacity (mx, x, t) e1 e2 -> do
      e1' <- elaborate' e1
      t' <- reduceType t
      e2' <- elaborate' e2
      return $ m :< TM.Let (WT.reifyOpacity opacity) (mx, x, t') e1' e2'
    m :< WT.Hole h es -> do
      fillHole m h es >>= elaborate'
    m :< WT.Prim prim ->
      case prim of
        WP.Type t ->
          return $ m :< TM.Prim (P.Type t)
        WP.Value primValue ->
          case primValue of
            WPV.Int t x -> do
              t' <- reduceWeakType t >>= elaborate'
              case t' of
                _ :< TM.Prim (P.Type (PT.Int size)) ->
                  return $ m :< TM.Prim (P.Value (PV.Int size x))
                _ :< TM.Prim (P.Type (PT.Float size)) ->
                  return $ m :< TM.Prim (P.Value (PV.Float size (fromInteger x)))
                _ -> do
                  Throw.raiseError m $
                    "the term `"
                      <> T.pack (show x)
                      <> "` is an integer, but its type is: "
                      <> toText (weaken t')
            WPV.Float t x -> do
              t' <- reduceWeakType t >>= elaborate'
              case t' of
                _ :< TM.Prim (P.Type (PT.Float size)) ->
                  return $ m :< TM.Prim (P.Value (PV.Float size x))
                _ -> do
                  Throw.raiseError m $
                    "the term `"
                      <> T.pack (show x)
                      <> "` is a float, but its type is: "
                      <> toText (weaken t')
            WPV.Op op ->
              return $ m :< TM.Prim (P.Value (PV.Op op))
            WPV.StaticText t text -> do
              t' <- elaborate' t
              return $ m :< TM.Prim (P.Value (PV.StaticText t' text))
    m :< WT.ResourceType name ->
      return $ m :< TM.ResourceType name
    m :< WT.Magic magic -> do
      case magic of
        M.External domList cod name args varArgs -> do
          let expected = length domList
          let actual = length args
          when (actual /= length domList) $ do
            Throw.raiseError m $
              "the external function `"
                <> EN.reify name
                <> "` expects "
                <> T.pack (show expected)
                <> " arguments, but found "
                <> T.pack (show actual)
                <> "."
          args' <- mapM elaborate' args
          varArgs' <- mapM (mapM elaborate') varArgs
          return $ m :< TM.Magic (M.External domList cod name args' varArgs')
        _ -> do
          magic' <- mapM elaborate' magic
          return $ m :< TM.Magic magic'
    m :< WT.Annotation remarkLevel annot e -> do
      e' <- elaborate' e
      case annot of
        AN.Type t -> do
          t' <- elaborate' t
          let message = "admitting `" <> toText (weaken t') <> "`"
          let typeRemark = Remark.newRemark m remarkLevel message
          Remark.insertRemark typeRemark
          return e'
    m :< WT.Flow pVar t -> do
      t' <- elaborate' t
      return $ m :< TM.Flow pVar t'
    m :< WT.FlowIntro pVar var (e, t) -> do
      e' <- elaborate' e
      t' <- elaborate' t
      return $ m :< TM.FlowIntro pVar var (e', t')
    m :< WT.FlowElim pVar var (e, t) -> do
      e' <- elaborate' e
      t' <- elaborate' t
      return $ m :< TM.FlowElim pVar var (e', t')

elaborateWeakBinder :: BinderF WT.WeakTerm -> App (BinderF TM.Term)
elaborateWeakBinder (m, x, t) = do
  t' <- elaborate' t
  return (m, x, t')

elaborateKind :: LK.LamKindF WT.WeakTerm -> App (LK.LamKindF TM.Term)
elaborateKind kind =
  case kind of
    LK.Normal opacity ->
      return $ LK.Normal opacity
    LK.Fix xt -> do
      xt' <- elaborateWeakBinder xt
      return $ LK.Fix xt'

fillHole ::
  Hint ->
  HID.HoleID ->
  [WT.WeakTerm] ->
  App WT.WeakTerm
fillHole m h es = do
  holeSubst <- getHoleSubst
  case HS.lookup h holeSubst of
    Nothing ->
      Throw.raiseError m $ "couldn't instantiate the hole here: " <> T.pack (show h)
    Just (xs, e)
      | length xs == length es -> do
          let s = IntMap.fromList $ zip (map Ident.toInt xs) (map Right es)
          WT.subst s e
      | otherwise ->
          Throw.raiseError m "arity mismatch"

elaborateDecisionTree :: Hint -> DT.DecisionTree WT.WeakTerm -> App (DT.DecisionTree TM.Term)
elaborateDecisionTree m tree =
  case tree of
    DT.Leaf xs body -> do
      body' <- elaborate' body
      return $ DT.Leaf xs body'
    DT.Unreachable ->
      return DT.Unreachable
    DT.Switch (cursor, cursorType) (fallbackClause, clauseList) -> do
      cursorType' <- reduceWeakType cursorType >>= elaborate'
      consList <- extractConstructorList m cursorType'
      let activeConsList = DT.getConstructors clauseList
      let diff = S.difference (S.fromList consList) (S.fromList activeConsList)
      if S.size diff == 0
        then do
          clauseList' <- mapM elaborateClause clauseList
          return $ DT.Switch (cursor, cursorType') (DT.Unreachable, clauseList')
        else do
          case fallbackClause of
            DT.Unreachable ->
              raiseNonExhaustivePatternMatching m
            _ -> do
              fallbackClause' <- elaborateDecisionTree m fallbackClause
              clauseList' <- mapM elaborateClause clauseList
              return $ DT.Switch (cursor, cursorType') (fallbackClause', clauseList')

elaborateClause :: DT.Case WT.WeakTerm -> App (DT.Case TM.Term)
elaborateClause decisionCase = do
  case decisionCase of
    DT.Cons mCons consName disc dataArgs consArgs cont -> do
      let (dataTerms, dataTypes) = unzip dataArgs
      dataTerms' <- mapM elaborate' dataTerms
      dataTypes' <- mapM elaborate' dataTypes
      consArgs' <- mapM elaborateWeakBinder consArgs
      cont' <- elaborateDecisionTree mCons cont
      return $ DT.Cons mCons consName disc (zip dataTerms' dataTypes') consArgs' cont'

raiseNonExhaustivePatternMatching :: Hint -> App a
raiseNonExhaustivePatternMatching m =
  Throw.raiseError m "encountered a non-exhaustive pattern matching"

reduceType :: WT.WeakTerm -> App TM.Term
reduceType e = do
  reduceWeakType e >>= elaborate'

reduceWeakType :: WT.WeakTerm -> App WT.WeakTerm
reduceWeakType e = do
  e' <- WT.reduce e
  case e' of
    m :< WT.Hole h es ->
      fillHole m h es >>= reduceWeakType
    m :< WT.PiElim (_ :< WT.VarGlobal name _) args -> do
      mLam <- WeakDefinition.lookup name
      case mLam of
        Just lam ->
          reduceWeakType $ m :< WT.PiElim lam args
        Nothing -> do
          return e'
    _ ->
      return e'

extractConstructorList :: Hint -> TM.Term -> App [DD.DefiniteDescription]
extractConstructorList m cursorType = do
  case cursorType of
    _ :< TM.Data _ consNameList _ -> do
      return consNameList
    _ ->
      Throw.raiseError m $ "the type of this term is expected to be an ADT, but it's not:\n" <> toText (weaken cursorType)
