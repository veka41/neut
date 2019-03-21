module Reduce where

import Data

import Control.Comonad

import Control.Comonad.Cofree
import Control.Monad.Except
import Control.Monad.Identity
import Control.Monad.State
import Control.Monad.Trans.Except
import Text.Show.Deriving

import Data.Functor.Classes

import System.IO.Unsafe

import Data.IORef
import Data.List
import Data.Maybe (fromMaybe)
import Data.Tuple (swap)

import qualified Text.Show.Pretty as Pr

reduce :: Neut -> WithEnv Neut
reduce (i :< NeutPi (x, tdom) tcod) = do
  tdom' <- reduce tdom
  tcod' <- reduce tcod
  return $ i :< NeutPi (x, tdom') tcod'
reduce app@(i :< NeutPiElim _ _) = do
  let (fun, args) = toPiElimSeq app
  args' <-
    forM args $ \(x, e) -> do
      e' <- reduce e
      return (x, e')
  fun' <- reduce fun
  case fun' of
    lam@(_ :< NeutPiIntro _ _)
      | (body, xtms) <- toPiIntroSeq lam
      , length xtms == length args -> do
        let xs = map (\(x, _, _) -> x) xtms
        let es = map snd args'
        reduce $ subst (zip xs es) body
    _ ->
      case takeConstApp fun' of
        Just constant
          | constant `elem` intAddConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x + y))
        Just constant
          | constant `elem` intSubConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x - y))
        Just constant
          | constant `elem` intMulConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x * y))
        Just constant
          | constant `elem` intDivConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x `div` y))
        _ -> return $ fromPiElimSeq (fun', args')
reduce (i :< NeutSigma xts) = do
  let (xs, ts) = unzip xts
  ts' <- mapM reduce ts
  let xts' = zip xs ts'
  return $ i :< NeutSigma xts'
reduce (i :< NeutSigmaIntro es) = do
  es' <- mapM reduce es
  return $ i :< NeutSigmaIntro es'
reduce (i :< NeutSigmaElim e xs body) = do
  e' <- reduce e
  case e of
    _ :< NeutSigmaIntro es -> do
      let _ :< body' = subst (zip xs es) body
      reduce $ i :< body'
    _ -> return $ i :< NeutSigmaElim e' xs body
reduce (i :< NeutIndexElim e branchList) = do
  e' <- reduce e
  case e' of
    _ :< NeutIndexIntro x ->
      case lookup (Left x) branchList of
        Just body -> reduce body
        Nothing ->
          case findIndexVariable branchList of
            Just (y, body) -> reduce $ subst [(y, e')] body
            Nothing ->
              case findDefault branchList of
                Just body -> reduce body
                Nothing ->
                  lift $
                  throwE $
                  "the index " ++ show x ++ " is not included in branchList"
    _ -> return $ i :< NeutIndexElim e' branchList
reduce (meta :< NeutMu s e) = reduce $ subst [(s, meta :< NeutMu s e)] e
reduce t = return t

reduce' :: Neut -> WithEnv Neut
reduce' (i :< NeutPi (x, tdom) tcod) = do
  tdom' <- reduce' tdom
  tcod' <- reduce' tcod
  return $ i :< NeutPi (x, tdom') tcod'
reduce' app@(i :< NeutPiElim _ _) = do
  let (fun, args) = toPiElimSeq app
  args' <-
    forM args $ \(x, e) -> do
      e' <- reduce' e
      return (x, e')
  fun' <- reduce' fun
  case fun' of
    lam@(_ :< NeutPiIntro _ _)
      | (body, xtms) <- toPiIntroSeq lam
      , length xtms == length args -> do
        let xs = map (\(x, _, _) -> x) xtms
        let es = map snd args'
        reduce' $ subst (zip xs es) body
    _ ->
      case takeConstApp fun' of
        Just constant
          | constant `elem` intAddConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x + y))
        Just constant
          | constant `elem` intSubConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x - y))
        Just constant
          | constant `elem` intMulConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x * y))
        Just constant
          | constant `elem` intDivConstantList
          , Just [x, y] <- takeIntegerList (map snd args') ->
            return $ i :< NeutIndexIntro (IndexInteger (x `div` y))
        _ -> return $ fromPiElimSeq (fun', args')
reduce' (i :< NeutSigma xts) = do
  let (xs, ts) = unzip xts
  ts' <- mapM reduce' ts
  return $ i :< NeutSigma (zip xs ts')
reduce' (i :< NeutSigmaIntro es) = do
  es' <- mapM reduce' es
  return $ i :< NeutSigmaIntro es'
reduce' (i :< NeutSigmaElim e xs body) = do
  e' <- reduce' e
  case e of
    _ :< NeutSigmaIntro es -> do
      let _ :< body' = subst (zip xs es) body
      reduce' $ i :< body'
    _ -> return $ i :< NeutSigmaElim e' xs body
reduce' (i :< NeutIndexElim e branchList) = do
  e' <- reduce' e
  case e' of
    _ :< NeutIndexIntro x ->
      case lookup (Left x) branchList of
        Just body -> reduce' body
        Nothing ->
          case findIndexVariable branchList of
            Just (y, body) -> reduce' $ subst [(y, e')] body
            Nothing ->
              case findDefault branchList of
                Just body -> reduce' body
                Nothing ->
                  lift $
                  throwE $
                  "the index " ++ show x ++ " is not included in branchList"
    _ -> return $ i :< NeutIndexElim e' branchList
reduce' (meta :< NeutMu s e) =
  return $ subst [(s, meta :< NeutMu s e)] e -- doesn't evaluate recursively
reduce' t = return t

toPiIntroSeq :: Neut -> (Neut, [(Identifier, Neut, Identifier)])
toPiIntroSeq (meta :< NeutPiIntro (x, t) body) = do
  let (body', args) = toPiIntroSeq body
  (body', (x, t, meta) : args)
toPiIntroSeq t = (t, [])

fromPiIntroSeq :: (Neut, [(Identifier, Neut, Identifier)]) -> Neut
fromPiIntroSeq (e, []) = e
fromPiIntroSeq (e, (x, t, meta):rest) = do
  let e' = fromPiIntroSeq (e, rest)
  meta :< NeutPiIntro (x, t) e'

toPiElimSeq :: Neut -> (Neut, [(Identifier, Neut)])
toPiElimSeq (i :< NeutPiElim e1 e2) = do
  let (fun, xs) = toPiElimSeq e1
  (fun, xs ++ [(i, e2)])
toPiElimSeq c = (c, [])

fromPiElimSeq :: (Neut, [(Identifier, Neut)]) -> Neut
fromPiElimSeq (term, []) = term
fromPiElimSeq (term, (i, v):xs) = fromPiElimSeq (i :< NeutPiElim term v, xs)

takeConstApp :: Neut -> Maybe Identifier
takeConstApp (_ :< NeutConst x) = Just x
takeConstApp _ = Nothing

takeIntegerList :: [Neut] -> Maybe [Int]
takeIntegerList [] = Just []
takeIntegerList ((_ :< NeutIndexIntro (IndexInteger i)):rest) = do
  is <- takeIntegerList rest
  return (i : is)
takeIntegerList _ = Nothing

findIndexVariable :: [(IndexOrVar, Neut)] -> Maybe (Identifier, Neut)
findIndexVariable [] = Nothing
findIndexVariable ((l, e):ls) =
  case getLabelIndex l of
    Just i -> Just (i, e)
    Nothing -> findIndexVariable ls

getLabelIndex :: IndexOrVar -> Maybe Identifier
getLabelIndex (Right x) = Just x
getLabelIndex _ = Nothing

findDefault :: [(IndexOrVar, Neut)] -> Maybe Neut
findDefault [] = Nothing
findDefault ((Left IndexDefault, e):_) = Just e
findDefault (_:rest) = findDefault rest

isReducible :: Neut -> Bool
isReducible (_ :< NeutVar _) = False
isReducible (_ :< NeutConst _) = False
isReducible (_ :< NeutPi (_, _) _) = False
isReducible (_ :< NeutPiIntro _ _) = False
isReducible (_ :< NeutPiElim (_ :< NeutPiIntro _ _) _) = True
isReducible (_ :< NeutPiElim e1 _) = isReducible e1
isReducible (_ :< NeutSigma _) = False
isReducible (_ :< NeutSigmaIntro es) = any isReducible es
isReducible (_ :< NeutSigmaElim (_ :< NeutSigmaIntro _) _ _) = True
isReducible (_ :< NeutSigmaElim e _ _) = isReducible e
isReducible (_ :< NeutIndex _) = False
isReducible (_ :< NeutIndexIntro _) = False
isReducible (_ :< NeutIndexElim (_ :< NeutIndexIntro _) _) = True
isReducible (_ :< NeutIndexElim e _) = isReducible e
isReducible (_ :< NeutUniv _) = False
isReducible (_ :< NeutMu _ _) = True
isReducible (_ :< NeutHole _) = False

isNonRecReducible :: Neut -> Bool
isNonRecReducible (_ :< NeutVar _) = False
isNonRecReducible (_ :< NeutConst _) = False
isNonRecReducible (_ :< NeutPi (_, tdom) tcod) =
  isNonRecReducible tdom || isNonRecReducible tcod
isNonRecReducible (_ :< NeutPiIntro _ _) = False
isNonRecReducible (_ :< NeutPiElim (_ :< NeutPiIntro _ _) _) = True
isNonRecReducible (_ :< NeutPiElim e1 _) = isNonRecReducible e1
isNonRecReducible (_ :< NeutSigma xts) = do
  let (_, ts) = unzip xts
  any isNonRecReducible ts
isNonRecReducible (_ :< NeutSigmaIntro es) = any isNonRecReducible es
isNonRecReducible (_ :< NeutSigmaElim (_ :< NeutSigmaIntro _) _ _) = True
isNonRecReducible (_ :< NeutSigmaElim e _ _) = isNonRecReducible e
isNonRecReducible (_ :< NeutIndex _) = False
isNonRecReducible (_ :< NeutIndexIntro _) = False
isNonRecReducible (_ :< NeutIndexElim (_ :< NeutIndexIntro _) _) = True
isNonRecReducible (_ :< NeutIndexElim e _) = isNonRecReducible e
isNonRecReducible (_ :< NeutUniv _) = False
isNonRecReducible (_ :< NeutMu _ _) = False
isNonRecReducible (_ :< NeutHole _) = False

nonRecReduce :: Neut -> WithEnv Neut
nonRecReduce e@(_ :< NeutVar _) = return e
nonRecReduce (i :< NeutPi (x, tdom) tcod) = do
  tdom' <- nonRecReduce tdom
  tcod' <- nonRecReduce tcod
  return $ i :< NeutPi (x, tdom') tcod'
nonRecReduce (i :< NeutPiIntro (x, tdom) e) = do
  e' <- nonRecReduce e
  return $ i :< NeutPiIntro (x, tdom) e'
nonRecReduce (i :< NeutPiElim e1 e2) = do
  e2' <- nonRecReduce e2
  e1' <- nonRecReduce e1
  case e1' of
    _ :< NeutPiIntro (arg, _) body -> do
      let sub = [(arg, e2')]
      let _ :< body' = subst sub body
      nonRecReduce $ i :< body'
    _ -> return $ i :< NeutPiElim e1' e2'
nonRecReduce (i :< NeutSigma xts) = do
  let (xs, ts) = unzip xts
  ts' <- mapM nonRecReduce ts
  return $ i :< NeutSigma (zip xs ts')
nonRecReduce (i :< NeutSigmaIntro es) = do
  es' <- mapM nonRecReduce es
  return $ i :< NeutSigmaIntro es'
nonRecReduce (i :< NeutSigmaElim e xs body) = do
  e' <- nonRecReduce e
  case e' of
    _ :< NeutSigmaIntro es -> do
      es' <- mapM nonRecReduce es
      let sub = zip xs es'
      let _ :< body' = subst sub body
      reduce $ i :< body'
    _ -> return $ i :< NeutSigmaElim e' xs body
nonRecReduce e@(_ :< NeutIndex _) = return e
nonRecReduce e@(_ :< NeutIndexIntro _) = return e
nonRecReduce (i :< NeutIndexElim e branchList) = do
  e' <- nonRecReduce e
  case e' of
    _ :< NeutIndexIntro x ->
      case lookup (Left x) branchList of
        Just body -> nonRecReduce body
        Nothing ->
          case findIndexVariable branchList of
            Just (y, body) -> nonRecReduce $ subst [(y, e')] body
            Nothing ->
              case findDefault branchList of
                Just body -> nonRecReduce body
                Nothing ->
                  lift $
                  throwE $
                  "the index " ++ show x ++ " is not included in branchList"
    _ -> do
      let (ls, es) = unzip branchList
      es' <- mapM nonRecReduce es
      return $ i :< NeutIndexElim e' (zip ls es')
nonRecReduce e@(_ :< NeutConst _) = return e
nonRecReduce e@(_ :< NeutUniv _) = return e
nonRecReduce e@(_ :< NeutMu _ _) = return e
nonRecReduce e@(_ :< NeutHole x) = do
  sub <- gets substitution
  case lookup x sub of
    Just e' -> return e'
    Nothing -> return e

reducePos :: Pos -> WithEnv Pos
reducePos (PosDownIntro e) = do
  e' <- reduceNeg e
  return $ PosDownIntro e'
reducePos e = return e

reduceNeg :: Neg -> WithEnv Neg
reduceNeg (NegPi (x, tdom) tcod) = do
  tdom' <- reducePos tdom
  tcod' <- reduceNeg tcod
  return $ NegPi (x, tdom') tcod'
reduceNeg (NegPiIntro x e) = do
  e' <- reduceNeg e
  return $ NegPiIntro x e'
reduceNeg (NegPiElim e1 e2) = do
  e1' <- reduceNeg e1
  case e1' of
    NegPiIntro x body -> do
      let sub = [(x, e2)]
      let body' = substNeg sub body
      reduceNeg body'
    _ -> return $ NegPiElim e1' e2
reduceNeg (NegSigmaElim e xs body) =
  case e of
    PosSigmaIntro es -> do
      let sub = zip xs es
      let body' = substNeg sub body
      reduceNeg body'
    _ -> do
      body' <- reduceNeg body
      return $ NegSigmaElim e xs body'
reduceNeg (NegIndexElim e branchList) =
  case e of
    PosIndexIntro x _ ->
      case lookup (Left x) branchList of
        Nothing ->
          lift $
          throwE $ "the index " ++ show x ++ " is not included in branchList"
        Just body -> reduceNeg body
    _ -> do
      let (labelList, es) = unzip branchList
      es' <- mapM reduceNeg es
      return $ NegIndexElim e $ zip labelList es'
reduceNeg (NegUp e) = do
  e' <- reducePos e
  return $ NegUp e'
reduceNeg (NegUpIntro e) = do
  e' <- reducePos e
  return $ NegUpIntro e'
reduceNeg (NegUpElim x e1 e2) = do
  e1' <- reduceNeg e1
  e2' <- reduceNeg e2
  case e1' of
    NegUpIntro e1'' -> reduceNeg $ substNeg [(x, e1'')] e2'
    _ -> return $ NegUpElim x e1' e2'
reduceNeg (NegDownElim e) = do
  e' <- reducePos e
  case e' of
    PosDownIntro e'' -> reduceNeg e''
    _ -> return $ NegDownElim e'
reduceNeg (NegMu x e) = do
  e' <- reduceNeg e
  return $ NegMu x e'

reduceValue :: Value -> WithEnv Value
reduceValue = return

reduceComp :: Comp -> WithEnv Comp
reduceComp (CompPi (x, tdom) tcod) = do
  tdom' <- reduceValue tdom
  tcod' <- reduceComp tcod
  return $ CompPi (x, tdom') tcod'
reduceComp (CompPiElimDownElim x xs) = return $ CompPiElimDownElim x xs
reduceComp (CompSigmaElim e xs body) = do
  body' <- reduceComp body
  return $ CompSigmaElim e xs body'
reduceComp (CompIndexElim e branchList) =
  case e of
    ValueIndexIntro x _ ->
      case lookup (Left x) branchList of
        Nothing ->
          lift $
          throwE $ "the index " ++ show x ++ " is not included in branchList"
        Just body -> reduceComp body
    _ -> do
      let (labelList, es) = unzip branchList
      es' <- mapM reduceComp es
      return $ CompIndexElim e $ zip labelList es'
reduceComp (CompUpIntro e) = do
  e' <- reduceValue e
  return $ CompUpIntro e'
reduceComp (CompUpElim x e1 e2) = do
  e1' <- reduceComp e1
  e2' <- reduceComp e2
  case e1' of
    CompUpIntro (ValueVar y) -> reduceComp $ substComp [(x, y)] e2'
    _ -> return $ CompUpElim x e1' e2'

subst :: Subst -> Neut -> Neut
subst sub (j :< NeutVar s) = fromMaybe (j :< NeutVar s) (lookup s sub)
subst _ (j :< NeutConst t) = j :< NeutConst t
subst sub (j :< NeutPi (s, tdom) tcod) = do
  let tdom' = subst sub tdom
  let sub' = filter (\(x, _) -> x /= s) sub
  let tcod' = subst sub' tcod
  j :< NeutPi (s, tdom') tcod'
subst sub (j :< NeutPiIntro (s, tdom) body) = do
  let tdom' = subst sub tdom
  let sub' = filter (\(x, _) -> x /= s) sub
  let body' = subst sub' body
  j :< NeutPiIntro (s, tdom') body'
subst sub (j :< NeutPiElim e1 e2) = do
  let e1' = subst sub e1
  let e2' = subst sub e2
  j :< NeutPiElim e1' e2'
subst sub (j :< NeutSigma xts) = j :< NeutSigma (substSigma sub xts)
subst sub (j :< NeutSigmaIntro es) = j :< NeutSigmaIntro (map (subst sub) es)
subst sub (j :< NeutSigmaElim e1 xs e2) = do
  let e1' = subst sub e1
  let sub' = filter (\(x, _) -> x `notElem` xs) sub
  let e2' = subst sub' e2
  j :< NeutSigmaElim e1' xs e2'
subst _ (j :< NeutIndex x) = j :< NeutIndex x
subst _ (j :< NeutIndexIntro l) = j :< NeutIndexIntro l
subst sub (j :< NeutIndexElim e branchList) = do
  let e' = subst sub e
  let branchList' =
        flip map branchList $ \(l, e) -> do
          let vs = varIndex l
          let sub' = filter (\(x, _) -> x `notElem` vs) sub
          (l, subst sub' e)
  j :< NeutIndexElim e' branchList'
subst _ (j :< NeutUniv i) = j :< NeutUniv i
subst sub (j :< NeutMu x e) = do
  let sub' = filter (\(y, _) -> x /= y) sub
  let e' = subst sub' e
  j :< NeutMu x e'
subst sub (j :< NeutHole s) = fromMaybe (j :< NeutHole s) (lookup s sub)

substSigma :: Subst -> [(Identifier, Neut)] -> [(Identifier, Neut)]
substSigma _ [] = []
substSigma sub ((x, t):rest) = do
  let sub' = filter (\(y, _) -> y /= x) sub
  let xts = substSigma sub' rest
  let t' = subst sub t
  (x, t') : xts

varIndex :: IndexOrVar -> [Identifier]
varIndex (Right x) = [x]
varIndex _ = []

type SubstPos = [(Identifier, Pos)]

substPos :: SubstPos -> Pos -> Pos
substPos sub (PosVar s) = fromMaybe (PosVar s) (lookup s sub)
substPos _ (PosConst x) = PosConst x
substPos sub (PosSigma xts) = do
  let (xs, ts) = unzip xts
  let ts' = map (substPos sub) ts
  PosSigma (zip xs ts')
substPos sub (PosSigmaIntro es) = do
  let es' = map (substPos sub) es
  PosSigmaIntro es'
substPos _ (PosIndex x) = PosIndex x
substPos _ (PosIndexIntro l meta) = PosIndexIntro l meta
substPos _ PosUniv = PosUniv
substPos sub (PosDown e) = do
  let e' = substNeg sub e
  PosDown e'
substPos sub (PosDownIntro e) = do
  let e' = substNeg sub e
  PosDownIntro e'

substNeg :: SubstPos -> Neg -> Neg
substNeg sub (NegPi (s, tdom) tcod) = do
  let tdom' = substPos sub tdom
  let tcod' = substNeg sub tcod
  NegPi (s, tdom') tcod'
substNeg sub (NegPiIntro s body) = do
  let body' = substNeg sub body
  NegPiIntro s body'
substNeg sub (NegPiElim e1 e2) = do
  let e1' = substNeg sub e1
  let e2' = substPos sub e2
  NegPiElim e1' e2'
substNeg sub (NegSigmaElim e1 xs e2) = do
  let e1' = substPos sub e1
  let e2' = substNeg sub e2
  NegSigmaElim e1' xs e2'
substNeg sub (NegIndexElim e branchList) = do
  let e' = substPos sub e
  let branchList' = map (\(l, e) -> (l, substNeg sub e)) branchList
  NegIndexElim e' branchList'
substNeg sub (NegUp e) = NegUp (substPos sub e)
substNeg sub (NegUpIntro e) = NegUpIntro (substPos sub e)
substNeg sub (NegUpElim x e1 e2) = do
  let e1' = substNeg sub e1
  let e2' = substNeg sub e2
  NegUpElim x e1' e2'
substNeg sub (NegDownElim e) = NegDownElim (substPos sub e)
substNeg sub (NegMu x e) = NegMu x $ substNeg sub e

type SubstValue = [(Identifier, Identifier)]

substValue :: SubstValue -> Value -> Value
substValue sub (ValueVar s) = do
  let s' = fromMaybe s (lookup s sub)
  ValueVar s'
substValue _ (ValueConst s) = ValueConst s
substValue sub (ValueSigma xts) = do
  let (xs, ts) = unzip xts
  let ts' = map (substValue sub) ts
  ValueSigma (zip xs ts')
substValue sub (ValueSigmaIntro es) = do
  let es' = map (substValue sub) es
  ValueSigmaIntro es'
substValue _ (ValueIndex x) = ValueIndex x
substValue _ (ValueIndexIntro l meta) = ValueIndexIntro l meta
substValue _ ValueUniv = ValueUniv

substComp :: SubstValue -> Comp -> Comp
substComp sub (CompPi (s, tdom) tcod) = do
  let tdom' = substValue sub tdom
  let tcod' = substComp sub tcod
  CompPi (s, tdom') tcod'
substComp sub (CompSigmaElim e1 xs e2) = do
  let e1' = substValue sub e1
  let e2' = substComp sub e2
  CompSigmaElim e1' xs e2'
substComp sub (CompIndexElim e branchList) = do
  let e' = substValue sub e
  let branchList' = map (\(l, e) -> (l, substComp sub e)) branchList
  CompIndexElim e' branchList'
substComp sub (CompUpIntro e) = CompUpIntro (substValue sub e)
substComp sub (CompUpElim x e1 e2) = do
  let e1' = substComp sub e1
  let e2' = substComp sub e2
  CompUpElim x e1' e2'

-- findInvVar :: Subst -> Identifier -> Maybe Identifier
-- findInvVar [] _ = Nothing
-- findInvVar ((y, _ :< NeutVar x):rest) x'
--   | x == x' =
--     if not (any (/= y) $ findInvVar' rest x')
--       then Just y
--       else Nothing
-- findInvVar ((_, _):rest) i = findInvVar rest i
-- findInvVar' :: Subst -> Identifier -> [Identifier]
-- findInvVar' [] _ = []
-- findInvVar' ((z, _ :< NeutVar x):rest) x'
--   | x /= x' = z : findInvVar' rest x'
-- findInvVar' (_:rest) x' = findInvVar' rest x'
type SubstIdent = [(Identifier, Identifier)]

substIdent :: SubstIdent -> Identifier -> Identifier
substIdent sub x = fromMaybe x (lookup x sub)

compose :: Subst -> Subst -> Subst
compose s1 s2 = do
  let domS2 = map fst s2
  let codS2 = map snd s2
  let codS2' = map (subst s1) codS2
  let fromS1 = filter (\(ident, _) -> ident `notElem` domS2) s1
  fromS1 ++ zip domS2 codS2'

reduceTerm :: Term -> WithEnv Term
reduceTerm (TermPiElim e1 e2) = do
  e2' <- reduceTerm e2
  e1' <- reduceTerm e1
  case e1' of
    TermPiIntro arg body -> do
      let sub = [(arg, e2')]
      let body' = substTerm sub body
      reduceTerm body'
    _ -> return $ TermPiElim e1' e2'
reduceTerm (TermSigmaIntro es) = do
  es' <- mapM reduceTerm es
  return $ TermSigmaIntro es'
reduceTerm (TermSigmaElim e xs body) = do
  e' <- reduceTerm e
  case e of
    TermSigmaIntro es -> do
      es' <- mapM reduceTerm es
      let body' = substTerm (zip xs es') body
      reduceTerm body'
    _ -> return $ TermSigmaElim e' xs body
reduceTerm (TermIndexElim e branchList) = do
  e' <- reduceTerm e
  case e' of
    TermIndexIntro x _ ->
      case lookup (Left x) branchList of
        Nothing ->
          lift $
          throwE $ "the index " ++ show x ++ " is not included in branchList"
        Just body -> reduceTerm body
    _ -> return $ TermIndexElim e' branchList
reduceTerm (TermMu s e) = do
  e' <- reduceTerm e
  return $ TermMu s e'
reduceTerm t = return t

type SubstTerm = [(Identifier, Term)]

substTerm :: SubstTerm -> Term -> Term
substTerm sub (TermVar s) = fromMaybe (TermVar s) (lookup s sub)
substTerm _ (TermConst x) = TermConst x
substTerm sub (TermPi (s, tdom) tcod) = do
  let tdom' = substTerm sub tdom
  let tcod' = substTerm sub tcod
  TermPi (s, tdom') tcod'
substTerm sub (TermPiIntro s body) = do
  let body' = substTerm sub body
  TermPiIntro s body'
substTerm sub (TermPiElim e1 e2) = do
  let e1' = substTerm sub e1
  let e2' = substTerm sub e2
  TermPiElim e1' e2'
substTerm sub (TermSigma xts) = do
  let (xs, ts) = unzip xts
  let ts' = map (substTerm sub) ts
  TermSigma $ zip xs ts'
substTerm sub (TermSigmaIntro es) = TermSigmaIntro (map (substTerm sub) es)
substTerm sub (TermSigmaElim e1 xs e2) = do
  let e1' = substTerm sub e1
  let e2' = substTerm sub e2
  TermSigmaElim e1' xs e2'
substTerm _ (TermIndex x) = TermIndex x
substTerm _ (TermIndexIntro l meta) = TermIndexIntro l meta
substTerm sub (TermIndexElim e branchList) = do
  let e' = substTerm sub e
  let branchList' = map (\(l, e) -> (l, substTerm sub e)) branchList
  TermIndexElim e' branchList'
substTerm _ (TermUniv i) = TermUniv i
substTerm sub (TermMu x e) = do
  let e' = substTerm sub e
  TermMu x e'
