{-# LANGUAGE TupleSections #-}

module Scene.Elaborate.Unify
  ( unify,
  )
where

import Context.Gensym
import Control.Comonad.Cofree
import Control.Exception.Safe
import Control.Monad
import qualified Data.HashMap.Lazy as Map
import Data.IORef
import qualified Data.IntMap as IntMap
import qualified Data.PQueue.Min as Q
import qualified Data.Set as S
import qualified Data.Text as T
import Entity.Binder
import Entity.Constraint
import Entity.FilePos
import Entity.Global
import Entity.Hint
import Entity.Ident
import qualified Entity.Ident.Reify as Ident
import Entity.LamKind
import Entity.Log
import Entity.Opacity
import Entity.WeakTerm
import Entity.WeakTerm.FreeVars
import Entity.WeakTerm.Holes
import Entity.WeakTerm.Reduce
import Entity.WeakTerm.Subst
import Entity.WeakTerm.ToText

data Stuck
  = StuckPiElimVarLocal Ident [(Hint, [WeakTerm])]
  | StuckPiElimVarGlobal T.Text [(Hint, [WeakTerm])]
  | StuckPiElimAster Int [[WeakTerm]]

unify :: Axis -> IO ()
unify axis =
  analyze axis >> synthesize axis

analyze :: Axis -> IO ()
analyze axis = do
  constraintList <- readIORef constraintListRef
  modifyIORef' constraintListRef $ const []
  simplify axis $ zip constraintList constraintList

synthesize :: Axis -> IO ()
synthesize axis = do
  suspendedConstraintQueue <- readIORef suspendedConstraintQueueRef
  case Q.minView suspendedConstraintQueue of
    Nothing ->
      return ()
    Just (SuspendedConstraint (_, ConstraintKindDelta c, (_, orig)), cs') -> do
      modifyIORef' suspendedConstraintQueueRef $ const cs'
      simplify axis [(c, orig)]
      synthesize axis
    Just (SuspendedConstraint (_, ConstraintKindOther, _), _) ->
      throwTypeErrors axis

throwTypeErrors :: Axis -> IO a
throwTypeErrors axis = do
  suspendedConstraintQueue <- readIORef suspendedConstraintQueueRef
  sub <- readIORef substRef
  errorList <- forM (Q.toList suspendedConstraintQueue) $ \(SuspendedConstraint (_, _, (_, (expected, actual)))) -> do
    -- p' foo
    -- p $ T.unpack $ toText l
    -- p $ T.unpack $ toText r
    -- p' (expected, actual)
    -- p' sub
    expected' <- subst axis sub expected >>= reduce axis
    actual' <- subst axis sub actual >>= reduce axis
    -- expected' <- subst sub l >>= reduce
    -- actual' <- subst sub r >>= reduce
    return $ logError (fromHint (metaOf actual)) $ constructErrorMsg actual' expected'
  throw $ Error errorList

constructErrorMsg :: WeakTerm -> WeakTerm -> T.Text
constructErrorMsg e1 e2 =
  "couldn't verify the definitional equality of the following two terms:\n- "
    <> toText e1
    <> "\n- "
    <> toText e2

simplify :: Axis -> [(Constraint, Constraint)] -> IO ()
simplify axis constraintList =
  case constraintList of
    [] ->
      return ()
    headConstraint@(c, orig) : cs -> do
      expected <- reduce axis $ fst c
      actual <- reduce axis $ snd c
      case (expected, actual) of
        (_ :< WeakTermTau, _ :< WeakTermTau) ->
          simplify axis cs
        (_ :< WeakTermVar x1, _ :< WeakTermVar x2)
          | x1 == x2 ->
            simplify axis cs
        (_ :< WeakTermVarGlobal g1, _ :< WeakTermVarGlobal g2)
          | g1 == g2 ->
            simplify axis cs
        (m1 :< WeakTermPi xts1 cod1, m2 :< WeakTermPi xts2 cod2)
          | length xts1 == length xts2 -> do
            xt1 <- asWeakBinder axis m1 cod1
            xt2 <- asWeakBinder axis m2 cod2
            cs' <- simplifyBinder axis orig (xts1 ++ [xt1]) (xts2 ++ [xt2])
            simplify axis $ cs' ++ cs
        (m1 :< WeakTermPiIntro kind1 xts1 e1, m2 :< WeakTermPiIntro kind2 xts2 e2)
          | LamKindFix xt1@(_, x1, _) <- kind1,
            LamKindFix xt2@(_, x2, _) <- kind2,
            x1 == x2,
            length xts1 == length xts2 -> do
            yt1 <- asWeakBinder axis m1 e1
            yt2 <- asWeakBinder axis m2 e2
            cs' <- simplifyBinder axis orig (xt1 : xts1 ++ [yt1]) (xt2 : xts2 ++ [yt2])
            simplify axis $ cs' ++ cs
          | LamKindNormal <- kind1,
            LamKindNormal <- kind2,
            length xts1 == length xts2 -> do
            xt1 <- asWeakBinder axis m1 e1
            xt2 <- asWeakBinder axis m2 e2
            cs' <- simplifyBinder axis orig (xts1 ++ [xt1]) (xts2 ++ [xt2])
            simplify axis $ cs' ++ cs
          | LamKindCons dataName1 consName1 consNumber1 dataType1 <- kind1,
            LamKindCons dataName2 consName2 consNumber2 dataType2 <- kind2,
            dataName1 == dataName2,
            consName1 == consName2,
            consNumber1 == consNumber2,
            length xts1 == length xts2 -> do
            xt1 <- asWeakBinder axis m1 e1
            xt2 <- asWeakBinder axis m2 e2
            cs' <- simplifyBinder axis orig (xts1 ++ [xt1]) (xts2 ++ [xt2])
            simplify axis $ ((dataType1, dataType2), orig) : cs' ++ cs
        (_ :< WeakTermSigma xts1, _ :< WeakTermSigma xts2)
          | length xts1 == length xts2 -> do
            cs' <- simplifyBinder axis orig xts1 xts2
            simplify axis $ cs' ++ cs
        (_ :< WeakTermSigmaIntro es1, _ :< WeakTermSigmaIntro es2)
          | length es1 == length es2 -> do
            simplify axis $ zipWith (curry (orig,)) es1 es2 ++ cs
        (_ :< WeakTermAster h1, _ :< WeakTermAster h2)
          | h1 == h2 ->
            simplify axis cs
        (_ :< WeakTermConst a1, _ :< WeakTermConst a2)
          | a1 == a2 ->
            simplify axis cs
        (_ :< WeakTermInt t1 l1, _ :< WeakTermInt t2 l2)
          | l1 == l2 ->
            simplify axis $ ((t1, t2), orig) : cs
        (_ :< WeakTermFloat t1 l1, _ :< WeakTermFloat t2 l2)
          | l1 == l2 ->
            simplify axis $ ((t1, t2), orig) : cs
        (_ :< WeakTermEnum a1, _ :< WeakTermEnum a2)
          | a1 == a2 ->
            simplify axis cs
        (_ :< WeakTermEnumIntro labelInfo1 a1, _ :< WeakTermEnumIntro labelInfo2 a2)
          | labelInfo1 == labelInfo2,
            a1 == a2 ->
            simplify axis cs
        (_ :< WeakTermQuestion e1 t1, _ :< WeakTermQuestion e2 t2) ->
          simplify axis $ ((e1, e2), orig) : ((t1, t2), orig) : cs
        (_ :< WeakTermNoema s1 e1, _ :< WeakTermNoema s2 e2) ->
          simplify axis $ ((s1, s2), orig) : ((e1, e2), orig) : cs
        (_ :< WeakTermNoemaIntro s1 e1, _ :< WeakTermNoemaIntro s2 e2)
          | s1 == s2 ->
            simplify axis $ ((e1, e2), orig) : cs
        (_ :< WeakTermArray elemType1, _ :< WeakTermArray elemType2) ->
          simplify axis $ ((elemType1, elemType2), orig) : cs
        (_ :< WeakTermArrayIntro elemType1 elems1, _ :< WeakTermArrayIntro elemType2 elems2) ->
          simplify axis $ ((elemType1, elemType2), orig) : zipWith (curry (orig,)) elems1 elems2 ++ cs
        (_ :< WeakTermText, _ :< WeakTermText) ->
          simplify axis cs
        (_ :< WeakTermTextIntro text1, _ :< WeakTermTextIntro text2)
          | text1 == text2 ->
            simplify axis cs
        (_ :< WeakTermCell contentType1, _ :< WeakTermCell contentType2) ->
          simplify axis $ ((contentType1, contentType2), orig) : cs
        (_ :< WeakTermCellIntro contentType1 content1, _ :< WeakTermCellIntro contentType2 content2) ->
          simplify axis $ ((contentType1, contentType2), orig) : ((content1, content2), orig) : cs
        (e1@(m1 :< _), e2@(m2 :< _)) -> do
          sub <- readIORef substRef
          termDefEnv <- readIORef termDefEnvRef
          let fvs1 = freeVars e1
          let fvs2 = freeVars e2
          let fmvs1 = holes e1
          let fmvs2 = holes e2
          let fmvs = S.union fmvs1 fmvs2 -- fmvs: free meta-variables
          case (lookupAny (S.toList fmvs1) sub, lookupAny (S.toList fmvs2) sub) of
            (Just (h1, body1), Just (h2, body2)) -> do
              let s1 = IntMap.singleton h1 body1
              let s2 = IntMap.singleton h2 body2
              e1' <- subst axis s1 e1
              e2' <- subst axis s2 e2
              simplify axis $ ((e1', e2'), orig) : cs
            (Just (h1, body1), Nothing) -> do
              let s1 = IntMap.singleton h1 body1
              e1' <- subst axis s1 e1
              simplify axis $ ((e1', e2), orig) : cs
            (Nothing, Just (h2, body2)) -> do
              let s2 = IntMap.singleton h2 body2
              e2' <- subst axis s2 e2
              simplify axis $ ((e1, e2'), orig) : cs
            (Nothing, Nothing) -> do
              case (asStuckedTerm e1, asStuckedTerm e2) of
                (Just (StuckPiElimAster h1 ies1), _)
                  | Just xss1 <- mapM asIdentList ies1,
                    Just argSet1 <- toLinearIdentSet xss1,
                    h1 `S.notMember` fmvs2,
                    fvs2 `S.isSubsetOf` argSet1 ->
                    resolveHole axis h1 xss1 e2 cs
                (_, Just (StuckPiElimAster h2 ies2))
                  | Just xss2 <- mapM asIdentList ies2,
                    Just argSet2 <- toLinearIdentSet xss2,
                    h2 `S.notMember` fmvs1,
                    fvs1 `S.isSubsetOf` argSet2 ->
                    resolveHole axis h2 xss2 e1 cs
                (Just (StuckPiElimVarLocal x1 mess1), Just (StuckPiElimVarLocal x2 mess2))
                  | x1 == x2,
                    Just pairList <- asPairList (map snd mess1) (map snd mess2) ->
                    simplify axis $ map (,orig) pairList ++ cs
                (Just (StuckPiElimVarGlobal g1 mess1), Just (StuckPiElimVarGlobal g2 mess2))
                  | g1 == g2,
                    Nothing <- lookupDefinition m1 g1 termDefEnv,
                    Just pairList <- asPairList (map snd mess1) (map snd mess2) ->
                    simplify axis $ map (,orig) pairList ++ cs
                (Just (StuckPiElimVarGlobal g1 mess1), Just (StuckPiElimVarGlobal g2 mess2))
                  | g1 == g2,
                    Just lam <- lookupDefinition m1 g1 termDefEnv ->
                    simplify axis $ ((toPiElim lam mess1, toPiElim lam mess2), orig) : cs
                (Just (StuckPiElimVarGlobal g1 mess1), Just (StuckPiElimVarGlobal g2 mess2))
                  | Just lam1 <- lookupDefinition m1 g1 termDefEnv,
                    Just lam2 <- lookupDefinition m2 g2 termDefEnv ->
                    simplify axis $ ((toPiElim lam1 mess1, toPiElim lam2 mess2), orig) : cs
                (Just (StuckPiElimVarGlobal g1 mess1), Just StuckPiElimAster {})
                  | Just lam <- lookupDefinition m1 g1 termDefEnv -> do
                    let uc = SuspendedConstraint (fmvs, ConstraintKindDelta (toPiElim lam mess1, e2), headConstraint)
                    modifyIORef' suspendedConstraintQueueRef $ Q.insert uc
                    simplify axis cs
                (Just StuckPiElimAster {}, Just (StuckPiElimVarGlobal g2 mess2))
                  | Just lam <- lookupDefinition m2 g2 termDefEnv -> do
                    let uc = SuspendedConstraint (fmvs, ConstraintKindDelta (e1, toPiElim lam mess2), headConstraint)
                    modifyIORef' suspendedConstraintQueueRef $ Q.insert uc
                    simplify axis cs
                (Just (StuckPiElimVarGlobal g1 mess1), _)
                  | Just lam <- lookupDefinition m1 g1 termDefEnv ->
                    simplify axis $ ((toPiElim lam mess1, e2), orig) : cs
                (_, Just (StuckPiElimVarGlobal g2 mess2))
                  | Just lam <- lookupDefinition m2 g2 termDefEnv ->
                    simplify axis $ ((e1, toPiElim lam mess2), orig) : cs
                _ -> do
                  let uc = SuspendedConstraint (fmvs, ConstraintKindOther, headConstraint)
                  modifyIORef' suspendedConstraintQueueRef $ Q.insert uc
                  simplify axis cs

{-# INLINE resolveHole #-}
resolveHole :: Axis -> Int -> [[BinderF WeakTerm]] -> WeakTerm -> [(Constraint, Constraint)] -> IO ()
resolveHole axis h1 xss e2' cs = do
  modifyIORef' substRef $ IntMap.insert h1 (toPiIntro xss e2')
  suspendedConstraintQueue <- readIORef suspendedConstraintQueueRef
  let (sus1, sus2) = Q.partition (\(SuspendedConstraint (hs, _, _)) -> S.member h1 hs) suspendedConstraintQueue
  modifyIORef' suspendedConstraintQueueRef $ const sus2
  let sus1' = map (\(SuspendedConstraint (_, _, c)) -> c) $ Q.toList sus1
  simplify axis $ sus1' ++ cs

simplifyBinder ::
  Axis ->
  Constraint ->
  [BinderF WeakTerm] ->
  [BinderF WeakTerm] ->
  IO [(Constraint, Constraint)]
simplifyBinder axis orig =
  simplifyBinder' axis orig IntMap.empty

simplifyBinder' ::
  Axis ->
  Constraint ->
  SubstWeakTerm ->
  [BinderF WeakTerm] ->
  [BinderF WeakTerm] ->
  IO [(Constraint, Constraint)]
simplifyBinder' axis orig sub args1 args2 =
  case (args1, args2) of
    ((m1, x1, t1) : xts1, (_, x2, t2) : xts2) -> do
      t2' <- subst axis sub t2
      let sub' = IntMap.insert (Ident.toInt x2) (m1 :< WeakTermVar x1) sub
      rest <- simplifyBinder' axis orig sub' xts1 xts2
      return $ ((t1, t2'), orig) : rest
    _ ->
      return []

asWeakBinder :: Axis -> Hint -> WeakTerm -> IO (BinderF WeakTerm)
asWeakBinder axis m t = do
  h <- newIdentFromText axis "aster"
  return (m, h, t)

asPairList ::
  [[WeakTerm]] ->
  [[WeakTerm]] ->
  Maybe [(WeakTerm, WeakTerm)]
asPairList list1 list2 =
  case (list1, list2) of
    ([], []) ->
      Just []
    (es1 : mess1, es2 : mess2)
      | length es1 /= length es2 ->
        Nothing
      | otherwise -> do
        pairList <- asPairList mess1 mess2
        return $ zip es1 es2 ++ pairList
    _ ->
      Nothing

asStuckedTerm :: WeakTerm -> Maybe Stuck
asStuckedTerm term =
  case term of
    (_ :< WeakTermVar x) ->
      Just $ StuckPiElimVarLocal x []
    (_ :< WeakTermVarGlobal g) ->
      Just $ StuckPiElimVarGlobal g []
    (_ :< WeakTermAster h) ->
      Just $ StuckPiElimAster h []
    (m :< WeakTermPiElim e es) ->
      case asStuckedTerm e of
        Just (StuckPiElimVarLocal x ess) ->
          Just $ StuckPiElimVarLocal x $ ess ++ [(m, es)]
        Just (StuckPiElimVarGlobal g ess) ->
          Just $ StuckPiElimVarGlobal g $ ess ++ [(m, es)]
        Just (StuckPiElimAster h iexss)
          | Just _ <- mapM asVar es ->
            Just $ StuckPiElimAster h $ iexss ++ [es]
        _ ->
          Nothing
    _ ->
      Nothing

toPiIntro :: [[BinderF WeakTerm]] -> WeakTerm -> WeakTerm
toPiIntro args e =
  case args of
    [] ->
      e
    xts : xtss -> do
      let e' = toPiIntro xtss e
      metaOf e' :< WeakTermPiIntro LamKindNormal xts e'

toPiElim :: WeakTerm -> [(Hint, [WeakTerm])] -> WeakTerm
toPiElim e args =
  case args of
    [] ->
      e
    (m, es) : ess ->
      toPiElim (m :< WeakTermPiElim e es) ess

asIdentList :: [WeakTerm] -> Maybe [BinderF WeakTerm]
asIdentList termList =
  case termList of
    [] ->
      return []
    e : es
      | (m :< WeakTermVar x) <- e -> do
        let t = m :< WeakTermTau -- don't care
        xts <- asIdentList es
        return $ (m, x, t) : xts
      | otherwise ->
        Nothing

{-# INLINE toLinearIdentSet #-}
toLinearIdentSet :: [[BinderF WeakTerm]] -> Maybe (S.Set Ident)
toLinearIdentSet xtss =
  toLinearIdentSet' xtss S.empty

toLinearIdentSet' :: [[BinderF WeakTerm]] -> S.Set Ident -> Maybe (S.Set Ident)
toLinearIdentSet' xtss acc =
  case xtss of
    [] ->
      return acc
    [] : rest ->
      toLinearIdentSet' rest acc
    ((_, x, _) : rest1) : rest2
      | x `S.member` acc ->
        Nothing
      | otherwise ->
        toLinearIdentSet' (rest1 : rest2) (S.insert x acc)

lookupAny :: [Int] -> IntMap.IntMap a -> Maybe (Int, a)
lookupAny is sub =
  case is of
    [] ->
      Nothing
    j : js ->
      case IntMap.lookup j sub of
        Just v ->
          Just (j, v)
        _ ->
          lookupAny js sub

{-# INLINE lookupDefinition #-}
lookupDefinition :: Hint -> T.Text -> Map.HashMap T.Text (Opacity, [BinderF WeakTerm], WeakTerm) -> Maybe WeakTerm
lookupDefinition m name termDefEnv =
  case Map.lookup name termDefEnv of
    Just (OpacityTransparent, xts, e) ->
      return $ m :< WeakTermPiIntro LamKindNormal xts e
    _ ->
      Nothing