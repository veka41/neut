{-# LANGUAGE OverloadedStrings #-}

module LLVM
  ( toLLVM
  ) where

import Control.Monad.Except
import Control.Monad.State

import qualified Data.HashMap.Strict as Map
import qualified Data.IntMap.Strict as IntMap
import qualified Data.Set as S
import qualified Data.Text as T

import Clarify.Utility
import Data.Basic
import Data.Code
import Data.Env hiding (newNameWith'')
import Data.LLVM
import Reduce.Code

toLLVM :: CodePlus -> WithEnv LLVM
toLLVM mainTerm@(m, _) = do
  mainTerm' <- reduceCodePlus mainTerm
  modify (\env -> env {nameSet = S.empty})
  mainTerm'' <- llvmCode mainTerm'
  -- the result of "main" must be i64, not i8*
  (result, resultVar) <- newDataUpsilonWith m "result"
  (cast, castThen) <- llvmCast (Just "cast") resultVar (LowTypeIntS 64)
  castResult <- castThen (LLVMReturn cast)
  -- let result: i8* := (main-term) in {cast result to i64}
  mainTerm''' <- commConv result mainTerm'' $ castResult
  snd <$> rename [] mainTerm'''

llvmCode :: CodePlus -> WithEnv LLVM
llvmCode (m, CodeTheta theta) = llvmCodeTheta m theta
llvmCode (_, CodePiElimDownElim v ds) = do
  (xs, vs) <- unzip <$> mapM (\d -> newDataLocal $ takeBaseName d) ds
  (fun, castThen) <- llvmCast (Just $ takeBaseName v) v $ toFunPtrType ds
  castThenCall <- castThen $ LLVMCall fun vs
  llvmDataLet' (zip xs ds) $ castThenCall
llvmCode (_, CodeSigmaElim k xs v e) = do
  let et = arrayKindToLowType k -- elem type
  let bt = LowTypeArrayPtr (length xs) et -- base pointer type  ([(length xs) x ARRAY_ELEM_TYPE])
  let idxList = map (\i -> (LLVMDataInt i, i32)) [0 ..]
  ys <- mapM newNameWith xs
  let xts' = zip xs (repeat et)
  let sizeInfo = (et, length xs)
  loadContent v bt sizeInfo (zip idxList (zip ys xts')) e
llvmCode (_, CodeUpIntro d) = do
  result <- newNameWith' $ takeBaseName d
  llvmDataLet result d $ LLVMReturn $ LLVMDataLocal result
llvmCode (_, CodeUpIntroNoReduce d) = do
  result <- newNameWith' $ takeBaseName d
  llvmDataLet result d $ LLVMReturn $ LLVMDataLocal result
llvmCode (_, CodeUpElim x e1 e2) = do
  e1' <- llvmCode e1
  e2' <- llvmCode e2
  commConv x e1' e2'
llvmCode (_, CodeEnumElim sub v branchList) = do
  let (ls, es) = unzip branchList
  let es' = map (substCodePlus sub) es
  ns <- gets nameSet
  modify (\env -> env {nameSet = S.empty})
  es'' <- mapM reduceCodePlus es'
  modify (\env -> env {nameSet = ns})
  llvmCodeEnumElim v $ zip ls es''
llvmCode (_, CodeStructElim xks v e) = do
  let (xs, ks) = unzip xks
  let ts = map arrayKindToLowType ks
  let xts = zip xs ts
  let bt = LowTypeStructPtr ts
  let idxList = map (\i -> (LLVMDataInt i, i32)) [0 ..]
  ys <- mapM newNameWith xs
  let sizeInfo = (LowTypeIntS64Ptr, length ts)
  loadContent v bt sizeInfo (zip idxList (zip ys xts)) e
llvmCode (m, CodeCase sub v branchList) = do
  let (ls, es) = unzip branchList
  let es' = map (substCodePlus sub) es
  ns <- gets nameSet
  modify (\env -> env {nameSet = S.empty})
  es'' <- mapM reduceCodePlus es'
  modify (\env -> env {nameSet = ns})
  llvmCodeCase m v $ zip ls es''

uncastList :: [(Identifier, (Identifier, LowType))] -> CodePlus -> WithEnv LLVM
uncastList [] e = llvmCode e
uncastList ((y, (x, et)):yxs) e = do
  e' <- uncastList yxs e
  llvmUncastLet x (LLVMDataLocal y) et e'

takeBaseName :: DataPlus -> T.Text
takeBaseName (_, DataTheta s) = s
takeBaseName (_, DataUpsilon (I (s, _))) = s
takeBaseName (_, DataSigmaIntro _ ds) = "array" <> T.pack (show (length ds))
takeBaseName (_, DataFloat16 _) = "half"
takeBaseName (_, DataFloat32 _) = "float"
takeBaseName (_, DataFloat64 _) = "double"
takeBaseName (_, DataEnumIntro (EnumValueIntS size _)) =
  "i" <> T.pack (show size)
takeBaseName (_, DataEnumIntro (EnumValueIntU size _)) =
  "u" <> T.pack (show size)
takeBaseName (_, DataEnumIntro _) = "i64"
takeBaseName (_, DataStructIntro dks) = "struct" <> T.pack (show (length dks))

takeBaseName' :: LLVMData -> T.Text
takeBaseName' (LLVMDataLocal (I (s, _))) = s
takeBaseName' (LLVMDataGlobal s) = s
takeBaseName' (LLVMDataInt _) = "int"
takeBaseName' (LLVMDataFloat16 _) = "half"
takeBaseName' (LLVMDataFloat32 _) = "float"
takeBaseName' (LLVMDataFloat64 _) = "double"
takeBaseName' LLVMDataNull = "null"

loadContent ::
     DataPlus -- base pointer
  -> LowType -- the type of base pointer
  -> SizeInfo
  -> [((LLVMData, LowType), (Identifier, (Identifier, LowType)))] -- [(the index of an element, the variable to load the element)]
  -> CodePlus -- continuation
  -> WithEnv LLVM
loadContent _ _ _ [] cont = llvmCode cont -- don't call redundant free
loadContent v bt sizeInfo iyxs cont = do
  let ixs = map (\(i, (y, (_, k))) -> (i, (y, k))) iyxs
  (bp, castThen) <- llvmCast (Just $ takeBaseName v) v bt
  let yxs = map (\(_, yx) -> yx) iyxs
  uncastThenCont <- uncastList yxs cont
  extractThenFreeThenUncastThenCont <-
    loadContent' bp bt sizeInfo ixs uncastThenCont
  castThen extractThenFreeThenUncastThenCont

loadContent' ::
     LLVMData -- base pointer
  -> LowType -- the type of base pointer
  -> SizeInfo
  -> [((LLVMData, LowType), (Identifier, LowType))] -- [(the index of an element, the variable to keep the loaded content)]
  -> LLVM -- continuation
  -> WithEnv LLVM
loadContent' bp bt sizeInfo [] cont = do
  l <- llvmUncast (Just $ takeBaseName' bp) bp bt
  tmp <- newNameWith'' $ Just $ takeBaseName' bp
  commConv tmp l $ LLVMCont (LLVMOpFree (LLVMDataLocal tmp) sizeInfo) cont
loadContent' bp bt sizeInfo ((i, (x, et)):xis) cont = do
  cont' <- loadContent' bp bt sizeInfo xis cont
  (posName, pos) <- newDataLocal' (Just $ asText x)
  return $
    LLVMLet
      posName
      (LLVMOpGetElementPtr (bp, bt) [(LLVMDataInt 0, LowTypeIntS 32), i]) $
    LLVMLet x (LLVMOpLoad pos et) cont'

llvmCodeTheta :: Meta -> Theta -> WithEnv LLVM
llvmCodeTheta _ (ThetaUnaryOp op v) = llvmCodeUnaryOp op v
llvmCodeTheta _ (ThetaBinaryOp op v1 v2) = llvmCodeBinaryOp op v1 v2
llvmCodeTheta _ (ThetaArrayAccess lowType arr idx) = do
  let arrayType = LowTypeArrayPtr 0 lowType
  (arrVar, castArrThen) <- llvmCast (Just $ takeBaseName arr) arr arrayType
  (idxVar, castIdxThen) <- llvmCast (Just $ takeBaseName idx) idx i64
  (resPtrName, resPtr) <- newDataLocal "result-ptr"
  resName <- newNameWith' "result"
  uncast <- llvmUncast (Just $ asText resName) (LLVMDataLocal resName) lowType
  (castArrThen >=> castIdxThen) $
    LLVMLet
      resPtrName
      (LLVMOpGetElementPtr
         (arrVar, arrayType)
         [(LLVMDataInt 0, i32), (idxVar, i64)])
      (LLVMLet resName (LLVMOpLoad resPtr lowType) uncast)
llvmCodeTheta _ (ThetaSysCall syscall args) = do
  (xs, vs) <- unzip <$> mapM (const $ newDataLocal "sys-call-arg") args
  call <- syscallToLLVM syscall vs
  llvmDataLet' (zip xs args) call

llvmCodeUnaryOp :: UnaryOp -> DataPlus -> WithEnv LLVM
llvmCodeUnaryOp op d = do
  let (domType, codType) = unaryOpToDomCod op
  (x, castThen) <- llvmCast (Just "unary-op") d domType
  result <- newNameWith' "unary-op-result"
  uncast <- llvmUncast (Just $ asText result) (LLVMDataLocal result) codType
  castThen $ LLVMLet result (LLVMOpUnaryOp op x) uncast

llvmCodeBinaryOp :: BinaryOp -> DataPlus -> DataPlus -> WithEnv LLVM
llvmCodeBinaryOp op v1 v2 = do
  let (domType, codType) = binaryOpToDomCod op
  (x1, cast1then) <- llvmCast (Just "binary-op-fst") v1 domType
  (x2, cast2then) <- llvmCast (Just "binary-op-snd") v2 domType
  result <- newNameWith' "binary-op-result"
  uncast <- llvmUncast (Just $ asText result) (LLVMDataLocal result) codType
  (cast1then >=> cast2then) $ LLVMLet result (LLVMOpBinaryOp op x1 x2) uncast

llvmCast ::
     Maybe T.Text
  -> DataPlus
  -> LowType
  -> WithEnv (LLVMData, LLVM -> WithEnv LLVM)
llvmCast mName v lowType@(LowTypeIntS _) = llvmCastInt mName v lowType
llvmCast mName v lowType@(LowTypeIntU _) = llvmCastInt mName v lowType
llvmCast mName v (LowTypeFloat i) = llvmCastFloat mName v i
llvmCast mName v ptrType = do
  tmp <- newNameWith'' mName
  x <- newNameWith'' mName
  return
    ( LLVMDataLocal x
    , \cont -> do
        llvmDataLet tmp v $
          LLVMLet x (LLVMOpBitcast (LLVMDataLocal tmp) voidPtr ptrType) cont)

llvmCastInt ::
     Maybe T.Text -- base name for newly created variables
  -> DataPlus
  -> LowType
  -> WithEnv (LLVMData, LLVM -> WithEnv LLVM)
llvmCastInt mName v lowType = do
  x <- newNameWith'' mName
  y <- newNameWith'' mName
  return
    ( LLVMDataLocal y
    , \cont -> do
        llvmDataLet x v $
          LLVMLet y (LLVMOpPointerToInt (LLVMDataLocal x) voidPtr lowType) $
          cont)

llvmCastFloat ::
     Maybe T.Text -- base name for newly created variables
  -> DataPlus
  -> FloatSize
  -> WithEnv (LLVMData, LLVM -> WithEnv LLVM)
llvmCastFloat mName v size = do
  let floatType = LowTypeFloat size
  let intType = LowTypeIntS $ sizeAsInt size
  (xName, x) <- newDataLocal' mName
  (yName, y) <- newDataLocal' mName
  z <- newNameWith'' mName
  return
    ( LLVMDataLocal z
    , \cont -> do
        llvmDataLet xName v $
          LLVMLet yName (LLVMOpPointerToInt x voidPtr intType) $
          LLVMLet z (LLVMOpBitcast y intType floatType) cont)

-- uncast: {some-concrete-type} -> voidPtr
llvmUncast :: Maybe T.Text -> LLVMData -> LowType -> WithEnv LLVM
llvmUncast mName result lowType@(LowTypeIntS _) =
  llvmUncastInt mName result lowType
llvmUncast mName result lowType@(LowTypeIntU _) =
  llvmUncastInt mName result lowType
llvmUncast mName result (LowTypeFloat i) = llvmUncastFloat mName result i
llvmUncast mName result ptrType = do
  x <- newNameWith'' mName
  return $
    LLVMLet x (LLVMOpBitcast result ptrType voidPtr) $
    LLVMReturn (LLVMDataLocal x)

llvmUncastInt :: Maybe T.Text -> LLVMData -> LowType -> WithEnv LLVM
llvmUncastInt mName result lowType = do
  x <- newNameWith'' mName
  return $
    LLVMLet x (LLVMOpIntToPointer result lowType voidPtr) $
    LLVMReturn (LLVMDataLocal x)

llvmUncastFloat :: Maybe T.Text -> LLVMData -> FloatSize -> WithEnv LLVM
llvmUncastFloat mName floatResult i = do
  let floatType = LowTypeFloat i
  let intType = LowTypeIntS $ sizeAsInt i
  tmp <- newNameWith'' mName
  x <- newNameWith'' mName
  return $
    LLVMLet tmp (LLVMOpBitcast floatResult floatType intType) $
    LLVMLet x (LLVMOpIntToPointer (LLVMDataLocal tmp) intType voidPtr) $
    LLVMReturn (LLVMDataLocal x)

llvmUncastLet :: Identifier -> LLVMData -> LowType -> LLVM -> WithEnv LLVM
llvmUncastLet x@(I (s, _)) d lowType cont = do
  l <- llvmUncast (Just s) d lowType
  commConv x l cont

-- LLVMLet x e1' e2'
-- `llvmDataLet x d cont` binds the data `d` to the variable `x`, and computes the
-- continuation `cont`.
llvmDataLet :: Identifier -> DataPlus -> LLVM -> WithEnv LLVM
llvmDataLet x (m, DataTheta y) cont = do
  cenv <- gets codeEnv
  ns <- gets nameSet
  case Map.lookup y cenv of
    Nothing -> raiseCritical m $ "no such global label defined: " <> y -- fixme: support FFI (update declEnv)
    Just (Definition _ args e)
      | not (y `S.member` ns) -> do
        modify (\env -> env {nameSet = S.insert y ns})
        llvm <- llvmCode e
        (args', llvm') <- rename args llvm
        insLLVMEnv y args' llvm'
        llvmUncastLet x (LLVMDataGlobal y) (toFunPtrType args) cont
      | otherwise -> do
        llvmUncastLet x (LLVMDataGlobal y) (toFunPtrType args) cont
llvmDataLet x (_, DataUpsilon y) cont =
  llvmUncastLet x (LLVMDataLocal y) voidPtr cont
llvmDataLet x (m, DataSigmaIntro k ds) cont = do
  let elemType = arrayKindToLowType k
  let arrayType = AggPtrTypeArray (length ds) elemType
  let dts = zip ds (repeat elemType)
  storeContent m x arrayType dts cont
llvmDataLet x (_, DataFloat16 f) cont =
  llvmUncastLet x (LLVMDataFloat16 f) (LowTypeFloat FloatSize16) cont
llvmDataLet x (_, DataFloat32 f) cont =
  llvmUncastLet x (LLVMDataFloat32 f) (LowTypeFloat FloatSize32) cont
llvmDataLet x (_, DataFloat64 f) cont =
  llvmUncastLet x (LLVMDataFloat64 f) (LowTypeFloat FloatSize64) cont
llvmDataLet x (m, DataEnumIntro intOrLabel) cont = do
  case intOrLabel of
    EnumValueIntS size i ->
      llvmUncastLet x (LLVMDataInt i) (LowTypeIntS size) cont
    EnumValueIntU size i ->
      llvmUncastLet x (LLVMDataInt i) (LowTypeIntU size) cont
    EnumValueLabel l -> do
      i <- toInteger <$> getEnumNum m l
      llvmUncastLet x (LLVMDataInt i) (LowTypeIntS 64) cont
llvmDataLet x (m, DataStructIntro dks) cont = do
  let (ds, ks) = unzip dks
  let ts = map arrayKindToLowType ks
  let structType = AggPtrTypeStruct ts
  storeContent m x structType (zip ds ts) cont

syscallToLLVM :: Syscall -> [LLVMData] -> WithEnv LLVM
syscallToLLVM syscall ds = do
  case syscall of
    Left name -> do
      denv <- gets declEnv
      when (not $ name `Map.member` denv) $ do
        let dom = map (const LowTypeVoidPtr) ds
        let cod = LowTypeVoidPtr
        modify (\env -> env {declEnv = Map.insert name (dom, cod) denv})
      return $ LLVMCall (LLVMDataGlobal name) ds
    Right (_, num) -> do
      res <- newNameWith' "result"
      return $
        LLVMLet res (LLVMOpSysCall num ds) $ LLVMReturn (LLVMDataLocal res)

llvmDataLet' :: [(Identifier, DataPlus)] -> LLVM -> WithEnv LLVM
llvmDataLet' [] cont = return cont
llvmDataLet' ((x, d):rest) cont = do
  cont' <- llvmDataLet' rest cont
  llvmDataLet x d cont'

-- returns Nothing iff the branch list is empty
constructSwitch :: [(Case, CodePlus)] -> WithEnv (Maybe (LLVM, [(Int, LLVM)]))
constructSwitch [] = return Nothing
constructSwitch [(CaseValue _, code)] = do
  code' <- llvmCode code
  return $ Just (code', [])
constructSwitch ((CaseValue l, code@(m, _)):rest) = do
  i <- fromInteger <$> enumValueToInteger m l
  code' <- llvmCode code
  mSwitch <- constructSwitch rest
  return $ do
    (defaultCase, caseList) <- mSwitch
    return (defaultCase, (i, code') : caseList)
constructSwitch ((CaseDefault, code):_) = do
  code' <- llvmCode code
  return $ Just (code', [])

llvmCodeEnumElim :: DataPlus -> [(Case, CodePlus)] -> WithEnv LLVM
llvmCodeEnumElim v branchList = do
  m <- constructSwitch branchList
  case m of
    Nothing -> return LLVMUnreachable
    Just (defaultCase, caseList) -> do
      let t = LowTypeIntS 64
      (cast, castThen) <- llvmCast (Just "enum-base") v t
      castThen $ LLVMSwitch (cast, t) defaultCase caseList

llvmCodeCase :: Meta -> DataPlus -> [(T.Text, CodePlus)] -> WithEnv LLVM
llvmCodeCase _ _ [] = return LLVMUnreachable
llvmCodeCase _ _ [(_, code)] = llvmCode code
llvmCodeCase m v ((c, code):branchList) = do
  funPtrType <- getLabelType m c
  code' <- llvmCode code
  cont <- llvmCodeCase m v branchList
  (tmp, tmpVar) <- newDataLocal c
  (base, baseVar) <- newDataLocal $ takeBaseName v
  (isEq, isEqVar) <- newDataLocal "cmp"
  uncastThenCmpThenBranch <-
    llvmUncastLet tmp (LLVMDataGlobal c) funPtrType $
    LLVMLet isEq (LLVMOpBinaryOp (BinaryOpEQ voidPtr) tmpVar baseVar) $
    LLVMBranch isEqVar code' cont
  llvmDataLet base v uncastThenCmpThenBranch

getLabelType :: Meta -> T.Text -> WithEnv LowType
getLabelType m c = do
  cenv <- gets codeEnv
  case Map.lookup c cenv of
    Just (Definition _ args _) -> return $ toFunPtrType args
    Nothing -> do
      let body = (m, CodeUpIntro (m, DataEnumIntro (EnumValueIntS 64 0)))
      insCodeEnv c [] body
      llvm <- llvmCode body
      insLLVMEnv c [] llvm
      return $ toFunPtrType []

data AggPtrType
  = AggPtrTypeArray Int LowType
  | AggPtrTypeStruct [LowType]

toLowType :: AggPtrType -> LowType
toLowType (AggPtrTypeArray i t) = LowTypeArrayPtr i t
toLowType (AggPtrTypeStruct ts) = LowTypeStructPtr ts

storeContent ::
     Meta
  -> Identifier
  -> AggPtrType
  -> [(DataPlus, LowType)]
  -> LLVM
  -> WithEnv LLVM
storeContent m reg aggPtrType dts cont = do
  let lowType = toLowType aggPtrType
  (cast, castThen) <- llvmCast (Just $ asText reg) (m, DataUpsilon reg) lowType
  storeThenCont <- storeContent' cast lowType (zip [0 ..] dts) cont
  castThenStoreThenCont <- castThen $ storeThenCont
  -- Use getelementptr to realize `sizeof`. More info:
  --   http://nondot.org/sabre/LLVMNotes/SizeOf-OffsetOf-VariableSizedStructs.txt
  case aggPtrType of
    AggPtrTypeStruct ts ->
      storeContent'' reg LowTypeIntS64Ptr (length ts) castThenStoreThenCont
    AggPtrTypeArray len t ->
      storeContent'' reg (LowTypePtr t) len castThenStoreThenCont

storeContent' ::
     LLVMData -- base pointer
  -> LowType -- the type of base pointer (like [n x u8]*, {i8*, i8*}*, etc.)
  -> [(Integer, (DataPlus, LowType))] -- [(the index of an element, the element to be stored)]
  -> LLVM -- continuation
  -> WithEnv LLVM
storeContent' _ _ [] cont = return cont
storeContent' bp bt ((i, (d, et)):ids) cont = do
  cont' <- storeContent' bp bt ids cont
  (locName, loc) <- newDataLocal $ takeBaseName d <> "-location"
  (cast, castThen) <- llvmCast (Just $ takeBaseName d) d et
  let it = indexTypeOf bt
  castThen $
    LLVMLet
      locName
      (LLVMOpGetElementPtr (bp, bt) [(LLVMDataInt 0, i32), (LLVMDataInt i, it)]) $
    LLVMCont (LLVMOpStore et cast loc) cont'

storeContent'' :: Identifier -> LowType -> Int -> LLVM -> WithEnv LLVM
storeContent'' reg elemPtrType size cont = do
  (c, cVar) <- newDataLocal $ "sizeof-" <> asText reg
  (i, iVar) <- newDataLocal $ "sizeof-" <> asText reg
  return $
    LLVMLet
      c
      (LLVMOpGetElementPtr
         (LLVMDataNull, elemPtrType)
         [(LLVMDataInt (toInteger size), i64)]) $
    LLVMLet i (LLVMOpPointerToInt cVar elemPtrType (LowTypeIntS 64)) $
    LLVMLet reg (LLVMOpAlloc iVar) cont

indexTypeOf :: LowType -> LowType
indexTypeOf (LowTypeStructPtr _) = LowTypeIntS 32
indexTypeOf _ = LowTypeIntS 64

arrayKindToLowType :: ArrayKind -> LowType
arrayKindToLowType (ArrayKindIntS i) = LowTypeIntS i
arrayKindToLowType (ArrayKindIntU i) = LowTypeIntU i
arrayKindToLowType (ArrayKindFloat size) = LowTypeFloat size
arrayKindToLowType ArrayKindVoidPtr = LowTypeVoidPtr

toFunPtrType :: [a] -> LowType
toFunPtrType xs = do
  LowTypeFunctionPtr (map (const voidPtr) xs) voidPtr

newDataLocal :: T.Text -> WithEnv (Identifier, LLVMData)
newDataLocal name = do
  x <- newNameWith' name
  return $ (x, LLVMDataLocal x)

newDataLocal' :: Maybe T.Text -> WithEnv (Identifier, LLVMData)
newDataLocal' mName = do
  x <- newNameWith'' mName
  return $ (x, LLVMDataLocal x)

i64 :: LowType
i64 = LowTypeIntS 64

i32 :: LowType
i32 = LowTypeIntS 32

newNameWith'' :: Maybe T.Text -> WithEnv Identifier
newNameWith'' Nothing = newNameWith' "var"
newNameWith'' (Just name) = newNameWith' name

enumValueToInteger :: Meta -> EnumValue -> WithEnv Integer
enumValueToInteger m intOrLabel =
  case intOrLabel of
    EnumValueLabel l -> toInteger <$> getEnumNum m l
    EnumValueIntS _ i -> return i
    EnumValueIntU _ i -> return i

getEnumNum :: Meta -> T.Text -> WithEnv Int
getEnumNum m label = do
  renv <- gets revEnumEnv
  case Map.lookup label renv of
    Nothing -> raiseCritical m $ "no such enum is defined: " <> label
    Just (_, i) -> return i

insLLVMEnv :: T.Text -> [Identifier] -> LLVM -> WithEnv ()
insLLVMEnv funName args e =
  modify (\env -> env {llvmEnv = Map.insert funName (args, e) (llvmEnv env)})

commConv :: Identifier -> LLVM -> LLVM -> WithEnv LLVM
commConv x (LLVMReturn d) cont =
  return $ LLVMLet x (LLVMOpBitcast d voidPtr voidPtr) cont -- nop
commConv x (LLVMLet y op cont1) cont2 = do
  cont <- commConv x cont1 cont2
  return $ LLVMLet y op cont
commConv x (LLVMCont op cont1) cont2 = do
  cont <- commConv x cont1 cont2
  return $ LLVMCont op cont
commConv x (LLVMSwitch (d, t) defaultCase caseList) cont2 = do
  let (ds, es) = unzip caseList
  es' <- mapM (\e -> commConv x e cont2) es
  let caseList' = zip ds es'
  defaultCase' <- commConv x defaultCase cont2
  return $ LLVMSwitch (d, t) defaultCase' caseList'
commConv x (LLVMBranch d onTrue onFalse) cont2 = do
  onTrue' <- commConv x onTrue cont2
  onFalse' <- commConv x onFalse cont2
  return $ LLVMBranch d onTrue' onFalse'
commConv x (LLVMCall d ds) cont2 = return $ LLVMLet x (LLVMOpCall d ds) cont2
commConv _ LLVMUnreachable _ = return LLVMUnreachable

rename :: [Identifier] -> LLVM -> WithEnv ([Identifier], LLVM)
rename args e = do
  args' <- mapM newNameWith args
  let is = map asInt args
  let js = map asInt args'
  l <- gets count
  (e', l') <- renameLLVM l (IntMap.fromList $ zip is js) e
  modify (\env -> env {count = l'})
  return (args', e')

type NameEnv = IntMap.IntMap Int

renameLLVMData :: NameEnv -> LLVMData -> WithEnv LLVMData
renameLLVMData nenv (LLVMDataLocal x@(I (s, i))) = do
  case IntMap.lookup i nenv of
    Just i' -> return $ LLVMDataLocal $ I (s, i')
    Nothing ->
      raiseCritical' $
      "found an unbound variable when renaming LLVM code: " <> asText' x
renameLLVMData _ d = return d

renameLLVM :: Int -> NameEnv -> LLVM -> WithEnv (LLVM, Int)
renameLLVM l nenv (LLVMReturn d) = do
  d' <- renameLLVMData nenv d
  return (LLVMReturn d', l)
renameLLVM l nenv (LLVMLet (I (s, i)) op cont) = do
  op' <- renameLLVMOp nenv op
  let x' = I (s, l)
  (cont', l') <- renameLLVM (l + 1) (IntMap.insert i l nenv) cont
  return (LLVMLet x' op' cont', l')
renameLLVM l nenv (LLVMCont op cont) = do
  op' <- renameLLVMOp nenv op
  (cont', l') <- renameLLVM l nenv cont
  return (LLVMCont op' cont', l')
renameLLVM l nenv (LLVMSwitch (d, t) defaultBranch les) = do
  let (ls, es) = unzip les
  d' <- renameLLVMData nenv d
  (defaultBranch', l') <- renameLLVM l nenv defaultBranch
  (es', l'') <- renameLLVM' l' nenv es
  return (LLVMSwitch (d', t) defaultBranch' (zip ls es'), l'')
renameLLVM l nenv (LLVMBranch d onTrue onFalse) = do
  d' <- renameLLVMData nenv d
  (onTrue', l') <- renameLLVM l nenv onTrue
  (onFalse', l'') <- renameLLVM l' nenv onFalse
  return (LLVMBranch d' onTrue' onFalse', l'')
renameLLVM l nenv (LLVMCall d ds) = do
  d' <- renameLLVMData nenv d
  ds' <- mapM (renameLLVMData nenv) ds
  return (LLVMCall d' ds', l)
renameLLVM l _ LLVMUnreachable = return (LLVMUnreachable, l)

renameLLVM' :: Int -> NameEnv -> [LLVM] -> WithEnv ([LLVM], Int)
renameLLVM' l _ [] = return ([], l)
renameLLVM' l nenv (e:es) = do
  (e', l') <- renameLLVM l nenv e
  (es', l'') <- renameLLVM' l' nenv es
  return (e' : es', l'')

renameLLVMOp :: NameEnv -> LLVMOp -> WithEnv LLVMOp
renameLLVMOp nenv (LLVMOpCall d ds) = do
  d' <- renameLLVMData nenv d
  ds' <- mapM (renameLLVMData nenv) ds
  return $ LLVMOpCall d' ds'
renameLLVMOp nenv (LLVMOpGetElementPtr (d, t) dts) = do
  d' <- renameLLVMData nenv d
  let (ds, ts) = unzip dts
  ds' <- mapM (renameLLVMData nenv) ds
  return $ LLVMOpGetElementPtr (d', t) (zip ds' ts)
renameLLVMOp nenv (LLVMOpBitcast d t1 t2) = do
  d' <- renameLLVMData nenv d
  return $ LLVMOpBitcast d' t1 t2
renameLLVMOp nenv (LLVMOpIntToPointer d t1 t2) = do
  d' <- renameLLVMData nenv d
  return $ LLVMOpIntToPointer d' t1 t2
renameLLVMOp nenv (LLVMOpPointerToInt d t1 t2) = do
  d' <- renameLLVMData nenv d
  return $ LLVMOpPointerToInt d' t1 t2
renameLLVMOp nenv (LLVMOpLoad d t) = do
  d' <- renameLLVMData nenv d
  return $ LLVMOpLoad d' t
renameLLVMOp nenv (LLVMOpStore t d1 d2) = do
  d1' <- renameLLVMData nenv d1
  d2' <- renameLLVMData nenv d2
  return $ LLVMOpStore t d1' d2'
renameLLVMOp nenv (LLVMOpAlloc d) = do
  d' <- renameLLVMData nenv d
  return $ LLVMOpAlloc d'
renameLLVMOp nenv (LLVMOpFree d sizeInfo) = do
  d' <- renameLLVMData nenv d
  return $ LLVMOpFree d' sizeInfo
renameLLVMOp nenv (LLVMOpUnaryOp op d) = do
  d' <- renameLLVMData nenv d
  return $ LLVMOpUnaryOp op d'
renameLLVMOp nenv (LLVMOpBinaryOp op d1 d2) = do
  d1' <- renameLLVMData nenv d1
  d2' <- renameLLVMData nenv d2
  return $ LLVMOpBinaryOp op d1' d2'
renameLLVMOp nenv (LLVMOpSysCall i ds) = do
  ds' <- mapM (renameLLVMData nenv) ds
  return $ LLVMOpSysCall i ds'
