module Reduce.Comp
  ( reduceComp,
    substComp,
  )
where

import Data.Basic hiding (asIdent)
import Data.Comp
import Data.Global
import qualified Data.HashMap.Lazy as Map
import Data.IORef
import qualified Data.IntMap as IntMap

type NameEnv = IntMap.IntMap Ident

reduceComp :: Comp -> IO Comp
reduceComp term =
  case term of
    CompPrimitive _ ->
      return term
    CompPiElimDownElim v ds -> do
      denv <- readIORef defEnv
      case v of
        ValueVarGlobal x
          | Just (isReducible, xs, Just body) <- Map.lookup x denv,
            isReducible,
            length xs == length ds -> do
            let sub = IntMap.fromList (zip (map asInt xs) ds)
            substComp sub IntMap.empty body >>= reduceComp
        _ ->
          return term
    CompSigmaElim isNoetic xs v e ->
      case v of
        ValueSigmaIntro ds
          | length ds == length xs -> do
            let sub = IntMap.fromList (zip (map asInt xs) ds)
            substComp sub IntMap.empty e >>= reduceComp
        _ -> do
          e' <- reduceComp e
          case e' of
            CompUpIntro (ValueSigmaIntro ds)
              | Just ys <- mapM asIdent ds,
                xs == ys ->
                return $ CompUpIntro v -- eta-reduce
            _ ->
              case xs of
                [] ->
                  return e'
                _ ->
                  return $ CompSigmaElim isNoetic xs v e'
    CompUpIntro _ ->
      return term
    CompUpElim x e1 e2 -> do
      e1' <- reduceComp e1
      case e1' of
        CompUpIntro d -> do
          let sub = IntMap.fromList [(asInt x, d)]
          substComp sub IntMap.empty e2 >>= reduceComp
        CompUpElim y ey1 ey2 ->
          reduceComp $ CompUpElim y ey1 $ CompUpElim x ey2 e2 -- commutative conversion
        CompSigmaElim b yts vy ey ->
          reduceComp $ CompSigmaElim b yts vy $ CompUpElim x ey e2 -- commutative conversion
        _ -> do
          e2' <- reduceComp e2
          case e2' of
            CompUpIntro (ValueVarLocal y)
              | x == y ->
                return e1' -- eta-reduce
            _ ->
              return $ CompUpElim x e1' e2'
    CompEnumElim v les ->
      case v of
        ValueEnumIntro path l
          | Just body <- lookup (EnumCaseLabel path l) les ->
            reduceComp body
          | Just body <- lookup EnumCaseDefault les ->
            reduceComp body
        ValueInt _ l
          | Just body <- lookup (EnumCaseInt (fromInteger l)) les ->
            reduceComp body
          | Just body <- lookup EnumCaseDefault les ->
            reduceComp body
          | otherwise -> do
            p "other"
            p' v
            p' les
            let (ls, es) = unzip les
            es' <- mapM reduceComp es
            return $ CompEnumElim v (zip ls es')
        _ -> do
          -- p "other"
          -- p' v
          -- p' les
          let (ls, es) = unzip les
          es' <- mapM reduceComp es
          return $ CompEnumElim v (zip ls es')
    CompIgnore e -> do
      e' <- reduceComp e
      return $ CompIgnore e'

substValue :: SubstValue -> NameEnv -> Value -> Value
substValue sub nenv term =
  case term of
    ValueVarLocal x
      | Just x' <- IntMap.lookup (asInt x) nenv ->
        ValueVarLocal x'
      | Just e <- IntMap.lookup (asInt x) sub ->
        e
      | otherwise ->
        term
    ValueSigmaIntro vs -> do
      let vs' = map (substValue sub nenv) vs
      ValueSigmaIntro vs'
    _ ->
      term

substComp :: SubstValue -> NameEnv -> Comp -> IO Comp
substComp sub nenv term =
  case term of
    CompPrimitive theta -> do
      let theta' = substPrimitive sub nenv theta
      return $ CompPrimitive theta'
    CompPiElimDownElim v ds -> do
      let v' = substValue sub nenv v
      let ds' = map (substValue sub nenv) ds
      return $ CompPiElimDownElim v' ds'
    CompSigmaElim b xs v e -> do
      let v' = substValue sub nenv v
      xs' <- mapM newIdentFromIdent xs
      let nenv' = IntMap.union (IntMap.fromList (zip (map asInt xs) xs')) nenv
      e' <- substComp sub nenv' e
      return $ CompSigmaElim b xs' v' e'
    CompUpIntro v -> do
      let v' = substValue sub nenv v
      return $ CompUpIntro v'
    CompUpElim x e1 e2 -> do
      e1' <- substComp sub nenv e1
      x' <- newIdentFromIdent x
      let nenv' = IntMap.insert (asInt x) x' nenv
      e2' <- substComp sub nenv' e2
      return $ CompUpElim x' e1' e2'
    CompEnumElim v branchList -> do
      let v' = substValue sub nenv v
      let (cs, es) = unzip branchList
      es' <- mapM (substComp sub nenv) es
      return $ CompEnumElim v' (zip cs es')
    CompIgnore e -> do
      e' <- substComp sub nenv e
      return $ CompIgnore e'

substPrimitive :: SubstValue -> NameEnv -> Primitive -> Primitive
substPrimitive sub nenv c =
  case c of
    PrimitivePrimOp op vs -> do
      let vs' = map (substValue sub nenv) vs
      PrimitivePrimOp op vs'
    PrimitiveDerangement expKind ds -> do
      let ds' = map (substValue sub nenv) ds
      PrimitiveDerangement expKind ds'

asIdent :: Value -> Maybe Ident
asIdent term =
  case term of
    ValueVarLocal x ->
      Just x
    _ ->
      Nothing
