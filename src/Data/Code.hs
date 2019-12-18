module Data.Code where

import Data.Maybe (fromMaybe)
import Numeric.Half

import Data.Basic

-- The definition of `Data` doesn't contain those type-level definitions like `DataTau`
-- since they are translated to "exponents" immediately after polarization (and thus in Polarize.hs).
data Data
  = DataTheta Identifier
  | DataUpsilon Identifier
  | DataEpsilonIntro Identifier
  | DataSigmaIntro [DataPlus]
  | DataInt Int LowType
  | DataFloat16 Half
  | DataFloat32 Float
  | DataFloat64 Double
  deriving (Show)

data Code
  = CodeTheta Theta
  | CodeEpsilonElim DataPlus [(Case, CodePlus)]
  | CodePiElimDownElim DataPlus [DataPlus] -- ((force v) v1 ... vn)
  | CodeSigmaElim [Identifier] DataPlus CodePlus
  | CodeUpIntro DataPlus
  | CodeUpElim Identifier CodePlus CodePlus
  deriving (Show)

data Theta
  = ThetaUnaryOp UnaryOp LowType DataPlus
  | ThetaBinaryOp BinaryOp LowType DataPlus DataPlus
  | ThetaPrint DataPlus
  deriving (Show)

type IdentifierPlus = (Identifier, DataPlus)

type CodeMeta = Maybe Loc

type DataPlus = (CodeMeta, Data)

type CodePlus = (CodeMeta, Code)

toDataUpsilon :: (Identifier, Maybe Loc) -> DataPlus
toDataUpsilon (x, ml) = (ml, DataUpsilon x)

type SubstDataPlus = [IdentifierPlus]

substDataPlus :: SubstDataPlus -> DataPlus -> DataPlus
substDataPlus _ (m, DataTheta x) = (m, DataTheta x)
substDataPlus sub (m, DataUpsilon s) =
  fromMaybe (m, DataUpsilon s) (lookup s sub)
substDataPlus _ (m, DataEpsilonIntro l) = (m, DataEpsilonIntro l)
substDataPlus sub (m, DataSigmaIntro vs) = do
  let vs' = map (substDataPlus sub) vs
  (m, DataSigmaIntro vs')
substDataPlus _ (m, DataInt l p) = (m, DataInt l p)
substDataPlus _ (m, DataFloat16 l) = (m, DataFloat16 l)
substDataPlus _ (m, DataFloat32 l) = (m, DataFloat32 l)
substDataPlus _ (m, DataFloat64 l) = (m, DataFloat64 l)

substCodePlus :: SubstDataPlus -> CodePlus -> CodePlus
substCodePlus sub (m, CodeTheta theta) = do
  let theta' = substTheta sub theta
  (m, CodeTheta theta')
substCodePlus sub (m, CodeEpsilonElim v branchList) = do
  let v' = substDataPlus sub v
  let (cs, es) = unzip branchList
  let es' = map (substCodePlus sub) es
  let branchList' = zip cs es'
  (m, CodeEpsilonElim v' branchList')
substCodePlus sub (m, CodePiElimDownElim v ds) = do
  let v' = substDataPlus sub v
  let ds' = map (substDataPlus sub) ds
  (m, CodePiElimDownElim v' ds')
substCodePlus sub (m, CodeSigmaElim xs v e) = do
  let v' = substDataPlus sub v
  let (xs', e') = substDataPlusSigmaElim sub xs e
  (m, CodeSigmaElim xs' v' e')
substCodePlus sub (m, CodeUpIntro v) = do
  let v' = substDataPlus sub v
  (m, CodeUpIntro v')
substCodePlus sub (m, CodeUpElim x e1 e2) = do
  let e1' = substCodePlus sub e1
  let e2' = substCodePlus sub e2
  (m, CodeUpElim x e1' e2')

substTheta :: SubstDataPlus -> Theta -> Theta
substTheta sub (ThetaUnaryOp a t v) = do
  let v' = substDataPlus sub v
  ThetaUnaryOp a t v'
substTheta sub (ThetaBinaryOp a t v1 v2) = do
  let v1' = substDataPlus sub v1
  let v2' = substDataPlus sub v2
  ThetaBinaryOp a t v1' v2'
substTheta sub (ThetaPrint v) = ThetaPrint $ substDataPlus sub v

substDataPlusPi ::
     SubstDataPlus -> [(Identifier, CodePlus)] -> [(Identifier, CodePlus)]
substDataPlusPi _ [] = []
substDataPlusPi sub ((x, p):xns) = do
  let xns' = substDataPlusPi (filter (\(y, _) -> y /= x) sub) xns
  (x, substCodePlus sub p) : xns'

substDataPlusSigma :: SubstDataPlus -> [IdentifierPlus] -> [IdentifierPlus]
substDataPlusSigma _ [] = []
substDataPlusSigma sub ((x, p):xps) = do
  let xps' = substDataPlusSigma (filter (\(y, _) -> y /= x) sub) xps
  (x, substDataPlus sub p) : xps'

substCodePlusPi ::
     SubstDataPlus
  -> [IdentifierPlus]
  -> CodePlus
  -> ([IdentifierPlus], CodePlus)
substCodePlusPi sub [] n = ([], substCodePlus sub n)
substCodePlusPi sub ((x, p):xps) n = do
  let (xps', n') = substCodePlusPi (filter (\(y, _) -> y /= x) sub) xps n
  let p' = substDataPlus sub p
  ((x, p') : xps', n')

substDataPlusSigmaElim ::
     SubstDataPlus -> [Identifier] -> CodePlus -> ([Identifier], CodePlus)
substDataPlusSigmaElim sub [] e = do
  let e' = substCodePlus sub e
  ([], e')
substDataPlusSigmaElim sub (x:xs) e = do
  let sub' = filter (\(y, _) -> y /= x) sub
  let (xs', e') = substDataPlusSigmaElim sub' xs e
  (x : xs', e')
