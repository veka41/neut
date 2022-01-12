{-# LANGUAGE TemplateHaskell #-}

module Parse.WeakTerm
  ( weakTerm,
    weakTermSimple,
    weakBinder,
    weakAscription,
    parseDefInfo,
  )
where

import Codec.Binary.UTF8.String (encode)
import Control.Comonad.Cofree (Cofree (..))
import Control.Monad (forM)
import Data.Basic
  ( BinderF,
    EnumCase,
    EnumCaseF (EnumCaseDefault, EnumCaseLabel),
    Hint,
    Ident,
    LamKindF (LamKindFix),
    PatternF,
    asIdent,
    asText,
  )
import Data.Global (constBoolFalse, constBoolTrue, newAster, outputError, targetArchRef, targetOSRef, targetPlatformRef, unsafePtr)
import Data.IORef (readIORef)
import Data.List (foldl')
import Data.Log (raiseError)
import Data.LowType
  ( Derangement (..),
    LowType (..),
    asLowFloat,
    asLowInt,
    showFloatSize,
    showIntSize,
  )
import qualified Data.Text as T
import Data.WeakTerm
  ( WeakDefInfo,
    WeakTerm,
    WeakTermF (..),
    metaOf,
  )
import Parse.Core
  ( argList,
    argList2,
    asBlock,
    betweenParen,
    char,
    currentHint,
    doBlock,
    float,
    inBlock,
    integer,
    isKeyword,
    isSymbolChar,
    lam,
    lookAhead,
    many,
    manyList,
    newTextualIdentFromText,
    raiseParseError,
    sepBy2,
    simpleSymbol,
    simpleVar,
    skip,
    string,
    symbol,
    symbolMaybe,
    token,
    tryPlanList,
    var,
    weakVar,
    weakVar',
  )

--
-- parser for WeakTerm
--

weakTerm :: IO WeakTerm
weakTerm = do
  headSymbol <- lookAhead (symbolMaybe isSymbolChar)
  case headSymbol of
    Just "lambda" ->
      weakTermPiIntro
    Just "define" ->
      weakTermPiIntroDef
    Just "*" ->
      weakTermAster
    Just "switch" ->
      weakTermEnumElim
    Just "introspect" ->
      weakTermIntrospect
    Just "question" ->
      weakTermQuestion
    Just "derangement" ->
      weakTermDerangement
    Just "match" ->
      weakTermMatch
    Just "match-noetic" ->
      weakTermMatchNoetic
    Just "let" ->
      weakTermLet
    Just "let?" ->
      weakTermLetCoproduct
    Just "if" ->
      weakTermIf
    Just "idealize" ->
      weakTermIdealize
    Just "new-array" ->
      weakTermArrayIntro
    Just headSymbolText
      | T.head headSymbolText == '&' -> do
        weakTermNoema
    _ ->
      tryPlanList
        [ weakTermPiArrow,
          weakTermSigma,
          weakTermAux
        ]

weakTermTau :: IO WeakTerm
weakTermTau = do
  m <- currentHint
  token "tau"
  return $ m :< WeakTermTau

weakTermAster :: IO WeakTerm
weakTermAster = do
  m <- currentHint
  token "?"
  newAster m

weakTermPiArrow :: IO WeakTerm
weakTermPiArrow = do
  m <- currentHint
  domList <- argList $ tryPlanList [weakAscription, typeWithoutIdent]
  token "->"
  cod <- weakTerm
  return $ m :< WeakTermPi domList cod

weakTermPiIntro :: IO WeakTerm
weakTermPiIntro = do
  m <- currentHint
  token "lambda"
  varList <- argList weakBinder
  e <- tryPlanList [weakTermDotBind, doBlock weakTerm]
  return $ lam m varList e

weakTermDotBind :: IO WeakTerm
weakTermDotBind = do
  char '.' >> skip
  weakTerm

parseDefInfo :: IO WeakDefInfo
parseDefInfo = do
  functionVar <- simpleVar
  domInfoList <- argList weakBinder
  char ':' >> skip
  codType <- weakTerm
  e <- asBlock weakTerm
  return (functionVar, domInfoList, codType, e)

-- define name(x1: A1, ..., xn: An)[: A] as e end
weakTermPiIntroDef :: IO WeakTerm
weakTermPiIntroDef = do
  m <- currentHint
  token "define"
  ((mFun, functionName), domBinderList, codType, e) <- parseDefInfo
  let piType = mFun :< WeakTermPi domBinderList codType
  return $ m :< WeakTermPiIntro (LamKindFix (mFun, asIdent functionName, piType)) domBinderList e

weakTermSigma :: IO WeakTerm
weakTermSigma = do
  m <- currentHint
  xts <- sepBy2 (token "*") weakTermSigmaItem
  toSigma m xts

weakTermSigmaItem :: IO (BinderF WeakTerm)
weakTermSigmaItem =
  tryPlanList
    [ betweenParen weakAscription,
      do
        m <- currentHint
        a <- tryPlanList [weakTermAux, weakTermTau, weakTermVar]
        h <- newTextualIdentFromText "_"
        return (m, h, a)
    ]

weakTermEnumElim :: IO WeakTerm
weakTermEnumElim = do
  m <- currentHint
  token "switch"
  e <- weakTerm
  token "with"
  clauseList <- many weakTermEnumClause
  token "end"
  h <- newAster m
  return $ m :< WeakTermEnumElim (e, h) clauseList

weakTermEnumClause :: IO (EnumCase, WeakTerm)
weakTermEnumClause = do
  m <- currentHint
  token "-"
  c <- symbol
  token "->"
  body <- weakTerm
  case c of
    "default" ->
      return (m :< EnumCaseDefault, body)
    _ ->
      return (m :< EnumCaseLabel c, body)

-- question e
weakTermQuestion :: IO WeakTerm
weakTermQuestion = do
  m <- currentHint
  token "question"
  e <- weakTerm
  h <- newAster m
  return $ m :< WeakTermQuestion e h

weakTermDerangement :: IO WeakTerm
weakTermDerangement = do
  m <- currentHint
  token "derangement"
  headSymbol <- symbol
  betweenParen $ do
    case headSymbol of
      "cast" -> do
        castFrom <- weakTerm
        castTo <- char ',' >> skip >> weakTerm
        value <- char ',' >> skip >> weakTerm
        return $ m :< WeakTermDerangement (DerangementCast castFrom castTo value)
      "store" -> do
        lt <- lowType
        pointer <- char ',' >> skip >> weakTerm
        value <- char ',' >> skip >> weakTerm
        return $ m :< WeakTermDerangement (DerangementStore lt pointer value)
      "load" -> do
        lt <- lowType
        pointer <- char ',' >> skip >> weakTerm
        return $ m :< WeakTermDerangement (DerangementLoad lt pointer)
      "syscall" -> do
        syscallNum <- integer
        es <- many (char ',' >> skip >> weakTerm)
        return $ m :< WeakTermDerangement (DerangementSyscall syscallNum es)
      "external" -> do
        extFunName <- symbol
        es <- many (char ',' >> skip >> weakTerm)
        return $ m :< WeakTermDerangement (DerangementExternal extFunName es)
      "create-array" -> do
        lt <- lowType
        es <- many (char ',' >> skip >> weakTerm)
        return $ m :< WeakTermDerangement (DerangementCreateArray lt es)
      _ ->
        raiseError m $ "no such derangement is defined: " <> headSymbol

-- t ::= i{n} | f{n} | pointer t | array INT t | struct t ... t
lowType :: IO LowType
lowType = do
  m <- currentHint
  headSymbol <- symbol
  case headSymbol of
    "pointer" ->
      LowTypePointer <$> lowTypeSimple
    "array" -> do
      intValue <- integer
      LowTypeArray (fromInteger intValue) <$> lowTypeSimple
    "struct" ->
      LowTypeStruct <$> many lowTypeSimple
    _
      | Just size <- asLowInt headSymbol ->
        return $ LowTypeInt size
      | Just size <- asLowFloat headSymbol ->
        return $ LowTypeFloat size
      | otherwise ->
        raiseParseError m "lowType"

lowTypeSimple :: IO LowType
lowTypeSimple =
  tryPlanList
    [ betweenParen lowType,
      lowTypeInt,
      lowTypeFloat
    ]

lowTypeInt :: IO LowType
lowTypeInt = do
  m <- currentHint
  headSymbol <- symbol
  case asLowInt headSymbol of
    Just size ->
      return $ LowTypeInt size
    Nothing ->
      raiseParseError m "lowTypeInt"

lowTypeFloat :: IO LowType
lowTypeFloat = do
  m <- currentHint
  headSymbol <- symbol
  case asLowFloat headSymbol of
    Just size ->
      return $ LowTypeFloat size
    Nothing ->
      raiseParseError m "lowTypeFloat"

weakTermMatch :: IO WeakTerm
weakTermMatch = do
  m <- currentHint
  token "match"
  e <- weakTerm
  clauseList <- inBlock "with" $ manyList weakTermMatchClause
  return $ m :< WeakTermMatch Nothing (e, doNotCare m) clauseList

weakTermMatchNoetic :: IO WeakTerm
weakTermMatchNoetic = do
  m <- currentHint
  token "match-noetic"
  e <- weakTerm
  token "with"
  s <- newAster m
  t <- newAster m
  let e' = castFromNoema s t e
  clauseList <- manyList weakTermMatchClause
  token "end"
  let clauseList' = map (modifyWeakPattern s) clauseList
  return $ m :< WeakTermMatch (Just s) (e', doNotCare m) clauseList'

weakTermMatchClause :: IO (PatternF WeakTerm, WeakTerm)
weakTermMatchClause = do
  pat <- weakTermPattern
  token "->"
  body <- weakTerm
  return (pat, body)

modifyWeakPattern :: WeakTerm -> (PatternF WeakTerm, WeakTerm) -> (PatternF WeakTerm, WeakTerm)
modifyWeakPattern s ((m, a, xts), body) =
  ((m, a, xts), modifyWeakPatternBody s xts body)

modifyWeakPatternBody :: WeakTerm -> [BinderF WeakTerm] -> WeakTerm -> WeakTerm
modifyWeakPatternBody s xts body =
  case xts of
    [] ->
      body
    ((m, x, t) : rest) ->
      bind (m, x, wrapWithNoema s t) (castToNoema s t (weakVar' m x)) $
        modifyWeakPatternBody s rest body

weakTermPattern :: IO (PatternF WeakTerm)
weakTermPattern = do
  m <- currentHint
  c <- symbol
  patArgs <- argList weakBinder
  return (m, c, patArgs)

-- let x : A = e1 in e2
-- let x     = e1 in e2
weakTermLet :: IO WeakTerm
weakTermLet =
  tryPlanList [weakTermLetSigmaElim, weakTermLetNormal]

weakTermLetNormal :: IO WeakTerm
weakTermLetNormal = do
  m <- currentHint
  token "let"
  x <- weakTermLetVar
  char '=' >> skip
  e1 <- weakTerm
  token "in"
  e2 <- weakTerm
  t1 <- newAster m
  resultType <- newAster m
  return $
    m
      :< WeakTermPiElim
        (weakVar m "core.identity.bind")
        [ t1,
          resultType,
          e1,
          lam m [x] e2
        ]

-- let (x1 : A1, ..., xn : An) = e1 in e2
weakTermLetSigmaElim :: IO WeakTerm
weakTermLetSigmaElim = do
  m <- currentHint
  token "let"
  xts <- argList2 weakBinder
  token "="
  e1 <- weakTerm
  token "in"
  e2 <- weakTerm
  resultType <- newAster m
  return $
    m
      :< WeakTermPiElim
        e1
        [ resultType,
          lam m xts e2
        ]

-- let? x : A = e1 in e2
-- let? x     = e1 in e2
weakTermLetCoproduct :: IO WeakTerm
weakTermLetCoproduct = do
  m <- currentHint
  token "let?"
  x <- weakTermLetVar
  char '=' >> skip
  e1 <- weakTerm
  token "in"
  e2 <- weakTerm
  err <- newTextualIdentFromText "err"
  typeOfLeft <- newAster m
  typeOfRight <- newAster m
  let sumLeft = "sum.left"
  let sumRight = "sum.right"
  let sumLeftVar = asIdent "sum.left"
  return $
    m
      :< WeakTermMatch
        Nothing
        (e1, doNotCare m)
        [ ( (m, sumLeft, [(m, err, typeOfLeft)]),
            m :< WeakTermPiElim (weakVar' m sumLeftVar) [typeOfLeft, typeOfRight, weakVar' m err]
          ),
          ( (m, sumRight, [x]),
            e2
          )
        ]

weakTermLetVar :: IO (BinderF WeakTerm)
weakTermLetVar = do
  m <- currentHint
  tryPlanList
    [ do
        x <- simpleSymbol
        char ':'
        skip
        a <- weakTerm
        return (m, asIdent x, a),
      do
        x <- simpleSymbol
        h <- newAster m
        return (m, asIdent x, h)
    ]

weakTermIf :: IO WeakTerm
weakTermIf = do
  m <- currentHint
  token "if"
  ifCond <- weakTerm
  token "then"
  ifBody <- weakTerm
  elseIfList <- many $ do
    token "else-if"
    elseIfCond <- weakTerm
    token "then"
    elseIfBody <- weakTerm
    return (elseIfCond, elseIfBody)
  token "else"
  elseBody <- weakTerm
  token "end"
  foldIf m ifCond ifBody elseIfList elseBody

foldIf :: Hint -> WeakTerm -> WeakTerm -> [(WeakTerm, WeakTerm)] -> WeakTerm -> IO WeakTerm
foldIf m ifCond ifBody elseIfList elseBody =
  case elseIfList of
    [] -> do
      h <- newAster m
      return $
        m
          :< WeakTermEnumElim
            (ifCond, h)
            [ (m :< EnumCaseLabel constBoolTrue, ifBody),
              (m :< EnumCaseLabel constBoolFalse, elseBody)
            ]
    ((elseIfCond, elseIfBody) : rest) -> do
      cont <- foldIf m elseIfCond elseIfBody rest elseBody
      h <- newAster m
      return $
        m
          :< WeakTermEnumElim
            (ifCond, h)
            [ (m :< EnumCaseLabel constBoolTrue, ifBody),
              (m :< EnumCaseLabel constBoolFalse, cont)
            ]

-- (e1, ..., en) (n >= 2)
weakTermSigmaIntro :: IO WeakTerm
weakTermSigmaIntro = do
  m <- currentHint
  es <- argList2 weakTerm
  xts <- forM es $ \_ -> do
    x <- newTextualIdentFromText "_"
    t <- newAster m
    return (m, x, t)
  sigVar <- newTextualIdentFromText "sigvar"
  k <- newTextualIdentFromText "sig-k"
  return $
    lam
      m
      [ (m, sigVar, m :< WeakTermTau),
        (m, k, m :< WeakTermPi xts (weakVar' m sigVar))
      ]
      (m :< WeakTermPiElim (weakVar' m k) es)

weakTermNoema :: IO WeakTerm
weakTermNoema = do
  m <- currentHint
  char '&'
  subject <- asIdent <$> simpleSymbol
  t <- weakTerm
  return $ m :< WeakTermNoema (m :< WeakTermVar subject) t

weakTermIdealize :: IO WeakTerm
weakTermIdealize = do
  m <- currentHint
  token "idealize"
  varList <- many simpleVar
  let varList' = fmap (fmap asIdent) varList
  token "over"
  subject <- asIdent <$> simpleSymbol
  e <- doBlock weakTerm
  ts <- mapM (\(mx, _) -> newAster mx) varList
  return $ m :< WeakTermNoemaElim subject (castLet subject (zip varList' ts) e)

castLet :: Ident -> [((Hint, Ident), WeakTerm)] -> WeakTerm -> WeakTerm
castLet subject xts cont =
  case xts of
    [] ->
      cont
    ((m, x), t) : rest ->
      bind (m, x, t) (m :< WeakTermNoemaIntro subject (weakVar' m x)) $ castLet subject rest cont

weakTermArrayIntro :: IO WeakTerm
weakTermArrayIntro = do
  m <- currentHint
  token "new-array"
  t <- lowTypeSimple
  es <- many weakTermSimple
  arr <- newTextualIdentFromText "arr"
  ptr <- newTextualIdentFromText "ptr"
  h1 <- newTextualIdentFromText "_"
  h2 <- newTextualIdentFromText "_"
  let ptrType = weakVar m unsafePtr
  let topType = weakVar m "top"
  arrText <- lowTypeToArrayKindText m t
  let arrName = arrText <> "-array" -- e.g. i8-array
  t' <- lowTypeToWeakTerm m t
  es' <- mapM (annotate t') es
  return $
    bind (m, arr, ptrType) (m :< WeakTermDerangement (DerangementCreateArray t es')) $
      bind (m, ptr, ptrType) (m :< WeakTermPiElim (weakVar m "memory.allocate") [intTerm m 16]) $
        bind (m, h1, topType) (m :< WeakTermPiElim (weakVar m "memory.store-i64-with-index") [weakVar m (asText ptr), intTerm m 0, intTerm m (toInteger (length es))]) $
          bind
            (m, h2, topType)
            (m :< WeakTermPiElim (weakVar m "memory.store-pointer-with-index") [weakVar m (asText ptr), intTerm m 1, weakVar m (asText arr)])
            (m :< WeakTermDerangement (DerangementCast (weakVar m unsafePtr) (weakVar m arrName) (weakVar m (asText ptr))))

lowTypeToWeakTerm :: Hint -> LowType -> IO WeakTerm
lowTypeToWeakTerm m t =
  case t of
    LowTypeInt s ->
      return (m :< WeakTermConst (showIntSize s))
    LowTypeFloat s ->
      return (m :< WeakTermConst (showFloatSize s))
    _ ->
      raiseParseError m "invalid argument passed to lowTypeToType"

annotate :: WeakTerm -> WeakTerm -> IO WeakTerm
annotate t e = do
  let m = metaOf e
  h <- newTextualIdentFromText "_"
  return $ bind (m, h, t) e $ weakVar m (asText h)

lowTypeToArrayKindText :: Hint -> LowType -> IO T.Text
lowTypeToArrayKindText m t =
  case t of
    LowTypeInt size ->
      return $ showIntSize size
    LowTypeFloat size ->
      return $ showFloatSize size
    _ ->
      raiseParseError m "unsupported array kind"

intTerm :: Hint -> Integer -> WeakTerm
intTerm m i =
  m :< WeakTermInt (m :< WeakTermConst "i64") i

bind :: BinderF WeakTerm -> WeakTerm -> WeakTerm -> WeakTerm
bind mxt@(m, _, _) e cont =
  m :< WeakTermPiElim (lam m [mxt] cont) [e]

weakTermAdmit :: IO WeakTerm
weakTermAdmit = do
  m <- currentHint
  token "admit"
  h <- newAster m
  return $
    m
      :< WeakTermPiElim
        (weakVar m "core.os.exit")
        [ h,
          m :< WeakTermInt (m :< WeakTermConst "i64") 1
        ]

weakTermAdmitQuestion :: IO WeakTerm
weakTermAdmitQuestion = do
  m <- currentHint
  token "?admit"
  h <- newAster m
  return $
    m
      :< WeakTermQuestion
        ( m
            :< WeakTermPiElim
              (weakVar m "os.exit")
              [ h,
                m :< WeakTermInt (m :< WeakTermConst "i64") 1
              ]
        )
        h

weakTermAux :: IO WeakTerm
weakTermAux = do
  m <- currentHint
  e <- weakTermSimple
  ess <- many $ argList weakTerm
  return $ foldl' (\base es -> m :< WeakTermPiElim base es) e ess

--
-- term-related helper functions
--

weakTermSimple :: IO WeakTerm
weakTermSimple =
  tryPlanList
    [ weakTermSigmaIntro,
      betweenParen weakTerm,
      weakTermTau,
      weakTermAster,
      weakTermString,
      weakTermInteger,
      weakTermFloat,
      weakTermAdmitQuestion,
      weakTermAdmit,
      weakTermVar
    ]

weakBinder :: IO (BinderF WeakTerm)
weakBinder =
  tryPlanList
    [ weakAscription,
      weakAscription'
    ]

weakAscription :: IO (BinderF WeakTerm)
weakAscription = do
  m <- currentHint
  x <- symbol
  char ':' >> skip
  a <- weakTerm
  return (m, asIdent x, a)

typeWithoutIdent :: IO (BinderF WeakTerm)
typeWithoutIdent = do
  m <- currentHint
  x <- newTextualIdentFromText "_"
  t <- weakTerm
  return (m, x, t)

weakAscription' :: IO (BinderF WeakTerm)
weakAscription' = do
  (m, x) <- weakSimpleIdent
  h <- newAster m
  return (m, x, h)

weakSimpleIdent :: IO (Hint, Ident)
weakSimpleIdent = do
  m <- currentHint
  x <- simpleSymbol
  if isKeyword x
    then raiseParseError m $ "found a keyword `" <> x <> "`, expecting a variable"
    else return (m, asIdent x)

weakTermIntrospect :: IO WeakTerm
weakTermIntrospect = do
  m <- currentHint
  token "introspect"
  key <- simpleSymbol
  value <- getIntrospectiveValue m key
  token "with"
  clauseList <- many weakTermIntrospectiveClause
  token "end"
  case lookup value clauseList of
    Just clause ->
      return clause
    Nothing -> do
      outputError m $ "`" <> value <> "` is not supported here"

weakTermIntrospectiveClause :: IO (T.Text, WeakTerm)
weakTermIntrospectiveClause = do
  token "-"
  c <- symbol
  token "->"
  body <- weakTerm
  return (c, body)

getIntrospectiveValue :: Hint -> T.Text -> IO T.Text
getIntrospectiveValue m key =
  case key of
    "target-platform" -> do
      T.pack <$> readIORef targetPlatformRef
    "target-arch" ->
      T.pack <$> readIORef targetArchRef
    "target-os" ->
      T.pack <$> readIORef targetOSRef
    _ ->
      raiseError m $ "no such introspective value is defined: " <> key

weakTermVar :: IO WeakTerm
weakTermVar = do
  (m, x) <- var
  return (weakVar m x)

weakTermString :: IO WeakTerm
weakTermString = do
  m <- currentHint
  s <- string
  let i8s = encode $ T.unpack s
  let len = toInteger $ length i8s
  let i8s' = map (\x -> m :< WeakTermInt (m :< WeakTermConst "i8") (toInteger x)) i8s
  return $
    m
      :< WeakTermPiElim
        (weakVar m "unsafe.create-new-string")
        [ m :< WeakTermInt (m :< WeakTermConst "i64") len,
          m
            :< WeakTermDerangement
              (DerangementCreateArray (LowTypeInt 8) i8s')
        ]

weakTermInteger :: IO WeakTerm
weakTermInteger = do
  m <- currentHint
  intValue <- integer
  h <- newAster m
  return $ m :< WeakTermInt h intValue

weakTermFloat :: IO WeakTerm
weakTermFloat = do
  m <- currentHint
  floatValue <- float
  h <- newAster m
  return $ m :< WeakTermFloat h floatValue

toSigma :: Hint -> [BinderF WeakTerm] -> IO WeakTerm
toSigma m xts = do
  sigVar <- newTextualIdentFromText "sig"
  h <- newTextualIdentFromText "_"
  return $
    m
      :< WeakTermPi
        [ (m, sigVar, m :< WeakTermTau),
          (m, h, m :< WeakTermPi xts (weakVar' m sigVar))
        ]
        (weakVar' m sigVar)

castFromNoema :: WeakTerm -> WeakTerm -> WeakTerm -> WeakTerm
castFromNoema subject baseType tree = do
  let m = metaOf tree
  m :< WeakTermDerangement (DerangementCast (wrapWithNoema subject baseType) baseType tree)

castToNoema :: WeakTerm -> WeakTerm -> WeakTerm -> WeakTerm
castToNoema subject baseType tree = do
  let m = metaOf tree
  m :< WeakTermDerangement (DerangementCast baseType (wrapWithNoema subject baseType) tree)

wrapWithNoema :: WeakTerm -> WeakTerm -> WeakTerm
wrapWithNoema subject baseType = do
  let m = metaOf baseType
  m :< WeakTermNoema subject baseType

doNotCare :: Hint -> WeakTerm
doNotCare m =
  m :< WeakTermTau