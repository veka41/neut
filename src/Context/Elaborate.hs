module Context.Elaborate
  ( initialize,
    initializeInferenceEnv,
    insConstraintEnv,
    insertActualityConstraint,
    setConstraintEnv,
    getConstraintEnv,
    insWeakTypeEnv,
    lookupWeakTypeEnv,
    lookupPreHoleEnv,
    lookupHoleEnv,
    insPreHoleEnv,
    insHoleEnv,
    insertSubst,
    newHole,
    newTypeHoleList,
    getHoleSubst,
    setHoleSubst,
  )
where

import Context.App
import Context.App.Internal
import Context.Gensym qualified as Gensym
import Context.Throw qualified as Throw
import Control.Comonad.Cofree
import Data.IntMap qualified as IntMap
import Entity.Binder
import Entity.Constraint qualified as C
import Entity.Hint
import Entity.HoleID qualified as HID
import Entity.HoleSubst qualified as HS
import Entity.Ident
import Entity.Ident.Reify qualified as Ident
import Entity.WeakTerm
import Entity.WeakTerm qualified as WT

type BoundVarEnv = [BinderF WT.WeakTerm]

initialize :: App ()
initialize = do
  initializeInferenceEnv
  writeRef' weakTypeEnv IntMap.empty

initializeInferenceEnv :: App ()
initializeInferenceEnv = do
  writeRef' constraintEnv []
  writeRef' holeEnv IntMap.empty

insConstraintEnv :: WeakTerm -> WeakTerm -> App ()
insConstraintEnv expected actual = do
  modifyRef' constraintEnv $ (:) (C.Eq expected actual)

insertActualityConstraint :: WeakTerm -> App ()
insertActualityConstraint t = do
  modifyRef' constraintEnv $ (:) (C.Actual t)

getConstraintEnv :: App [C.Constraint]
getConstraintEnv =
  readRef' constraintEnv

setConstraintEnv :: [C.Constraint] -> App ()
setConstraintEnv =
  writeRef' constraintEnv

insWeakTypeEnv :: Ident -> WeakTerm -> App ()
insWeakTypeEnv k v =
  modifyRef' weakTypeEnv $ IntMap.insert (Ident.toInt k) v

lookupWeakTypeEnv :: Hint -> Ident -> App WeakTerm
lookupWeakTypeEnv m k = do
  wtenv <- readRef' weakTypeEnv
  case IntMap.lookup (Ident.toInt k) wtenv of
    Just t ->
      return t
    Nothing ->
      Throw.raiseCritical m $
        Ident.toText' k <> " is not found in the weak type environment."

lookupHoleEnv :: Int -> App (Maybe (WeakTerm, WeakTerm))
lookupHoleEnv i =
  IntMap.lookup i <$> readRef' holeEnv

lookupPreHoleEnv :: Int -> App (Maybe WeakTerm)
lookupPreHoleEnv i =
  IntMap.lookup i <$> readRef' preHoleEnv

insHoleEnv :: Int -> WeakTerm -> WeakTerm -> App ()
insHoleEnv i e1 e2 =
  modifyRef' holeEnv $ IntMap.insert i (e1, e2)

insPreHoleEnv :: Int -> WeakTerm -> App ()
insPreHoleEnv i e =
  modifyRef' preHoleEnv $ IntMap.insert i e

insertSubst :: HID.HoleID -> [Ident] -> WT.WeakTerm -> App ()
insertSubst holeID xs e =
  modifyRef' holeSubst $ HS.insert holeID xs e

getHoleSubst :: App HS.HoleSubst
getHoleSubst =
  readRef' holeSubst

setHoleSubst :: HS.HoleSubst -> App ()
setHoleSubst =
  writeRef' holeSubst

newHole :: Hint -> BoundVarEnv -> App WT.WeakTerm
newHole m varEnv = do
  Gensym.newHole m $ map (\(mx, x, _) -> mx :< WT.Var x) varEnv

-- In context varEnv == [x1, ..., xn], `newTypeHoleList varEnv [y1, ..., ym]` generates
-- the following list:
--
--   [(y1,   ?M1   @ (x1, ..., xn)),
--    (y2,   ?M2   @ (x1, ..., xn, y1),
--    ...,
--    (y{m}, ?M{m} @ (x1, ..., xn, y1, ..., y{m-1}))]
--
-- inserting type information `yi : ?Mi @ (x1, ..., xn, y1, ..., y{i-1})
newTypeHoleList :: BoundVarEnv -> [(Ident, Hint)] -> App [BinderF WT.WeakTerm]
newTypeHoleList varEnv ids =
  case ids of
    [] ->
      return []
    ((x, m) : rest) -> do
      t <- newHole m varEnv
      insWeakTypeEnv x t
      ts <- newTypeHoleList ((m, x, t) : varEnv) rest
      return $ (m, x, t) : ts
