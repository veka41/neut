module Data.Constraint where

import Data.PreTerm

type PreConstraint = (PreTermPlus, PreTermPlus)

data Constraint
  = ConstraintAnalyzable
  | ConstraintPattern Hole [[PreTermPlus]] PreTermPlus
  | ConstraintDelta PreTermPlus [(PreMeta, [PreTermPlus])] PreTermPlus
  | ConstraintQuasiPattern Hole [[PreTermPlus]] PreTermPlus
  | ConstraintFlexRigid Hole [[PreTermPlus]] PreTermPlus
  | ConstraintOther
  deriving (Show)

constraintToInt :: Constraint -> Int
constraintToInt ConstraintAnalyzable = 0
constraintToInt ConstraintPattern {} = 1
constraintToInt ConstraintDelta {} = 2
constraintToInt ConstraintQuasiPattern {} = 3
constraintToInt ConstraintFlexRigid {} = 4
constraintToInt ConstraintOther = 5

instance Eq Constraint where
  c1 == c2 = constraintToInt c1 == constraintToInt c2

instance Ord Constraint where
  compare c1 c2 = compare (constraintToInt c1) (constraintToInt c2)

data EnrichedConstraint =
  Enriched
    PreConstraint
    [Hole] -- list of metavariables that cause stuck
    Constraint
  deriving (Show)

instance Eq EnrichedConstraint where
  (Enriched _ _ c1) == (Enriched _ _ c2) = c1 == c2

instance Ord EnrichedConstraint where
  compare (Enriched _ _ c1) (Enriched _ _ c2) = compare c1 c2

-- s1が新たに追加されるsubstで、s2が既存のsubst
-- s1 = m ~> eとして、eのなかにs2でsubstされるべきholeが含まれているとする。
compose :: SubstPreTerm -> SubstPreTerm -> SubstPreTerm
compose s1 s2 = do
  let domS2 = map fst s2
  let codS2 = map snd s2
  let codS2' = map (substPreTermPlus s1) codS2
  let s1' = filter (\(ident, _) -> ident `notElem` domS2) s1
  s1' ++ zip domS2 codS2'
