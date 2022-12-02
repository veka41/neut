module Entity.WeakTerm.ToText (toText) where

import Control.Comonad.Cofree
import qualified Data.Text as T
import Entity.Binder
import qualified Entity.DecisionTree as DT
import qualified Entity.DefiniteDescription as DD
import qualified Entity.Discriminant as D
import qualified Entity.EnumCase as EC
import qualified Entity.EnumTypeName as ET
import qualified Entity.EnumValueName as EV
import Entity.Hint
import qualified Entity.HoleID as HID
import Entity.Ident
import qualified Entity.Ident.Reify as Ident
import qualified Entity.LamKind as LK
import qualified Entity.PrimOp as PO
import qualified Entity.PrimType.ToText as PT
import qualified Entity.WeakPrim as WP
import qualified Entity.WeakPrimValue as WPV
import qualified Entity.WeakTerm as WT

toText :: WT.WeakTerm -> T.Text
toText term =
  case term of
    _ :< WT.Tau ->
      "tau"
    _ :< WT.Var x ->
      showVariable x
    _ :< WT.VarGlobal x _ ->
      DD.reify x
    _ :< WT.Pi xts cod
      | [(_, I ("internal.sigma-tau", _), _), (_, _, _ :< WT.Pi yts _)] <- xts ->
          case splitLast yts of
            Nothing ->
              "(product)"
            Just (zts, (_, _, t)) ->
              showCons ["∑", inParen $ showTypeArgs zts, toText t]
      | otherwise ->
          showCons ["Π", inParen $ showTypeArgs xts, toText cod]
    _ :< WT.PiIntro kind xts e -> do
      case kind of
        LK.Fix (_, x, _) -> do
          let argStr = inParen $ showItems $ map showArg xts
          showCons ["fix", showVariable x, argStr, toText e]
        _ -> do
          let argStr = inParen $ showItems $ map showArg xts
          showCons ["λ", argStr, toText e]
    _ :< WT.PiElim e es ->
      showCons $ map toText $ e : es
    _ :< WT.Data name es -> do
      showCons $ DD.reify name : map toText es
    _ :< WT.DataIntro _ consName _ _ consArgs -> do
      showCons (DD.reify consName : map toText consArgs)
    _ :< WT.DataElim xets tree -> do
      let (xs, es, _) = unzip3 xets
      showCons ["match", showMatchArgs (zip xs es), showDecisionTree tree]
    _ :< WT.Sigma xts ->
      showCons ["sigma", showItems $ map showArg xts]
    _ :< WT.SigmaIntro es ->
      showCons $ "sigma-intro" : map toText es
    _ :< WT.SigmaElim {} ->
      "<sigma-elim>"
    _ :< WT.Let (_, x, _) e1 e2 -> do
      showCons ["let", showVariable x, toText e1, toText e2]
    _ :< WT.Prim prim ->
      showPrim prim
    _ :< WT.Aster i es ->
      showCons $ "?M" <> T.pack (show (HID.reify i)) : map toText es
    _ :< WT.Enum l ->
      DD.reify $ ET.reify l
    _ :< WT.EnumIntro (EC.EnumLabel _ _ v) ->
      DD.reify $ EV.reify v
    _ :< WT.EnumElim (e, _) mles -> do
      showCons ["switch", toText e, showItems (map showClause mles)]
    _ :< WT.Question e _ ->
      toText e
    _ :< WT.Magic m -> do
      let a = fmap toText m
      T.pack $ show a

inParen :: T.Text -> T.Text
inParen s =
  "(" <> s <> ")"

showArg :: (Hint, Ident, WT.WeakTerm) -> T.Text
showArg (_, x, t) =
  inParen $ showVariable x <> " " <> toText t

showTypeArgs :: [BinderF WT.WeakTerm] -> T.Text
showTypeArgs args =
  case args of
    [] ->
      T.empty
    [(_, x, t)] ->
      inParen $ showVariable x <> " " <> toText t
    (_, x, t) : xts -> do
      let s1 = inParen $ showVariable x <> " " <> toText t
      let s2 = showTypeArgs xts
      s1 <> " " <> s2

showVariable :: Ident -> T.Text
showVariable =
  Ident.toText'

showClause :: (EC.EnumCase, WT.WeakTerm) -> T.Text
showClause (c, e) =
  inParen $ showCase c <> " " <> toText e

showCase :: EC.EnumCase -> T.Text
showCase c =
  case c of
    _ :< EC.Label (EC.EnumLabel _ _ l) ->
      DD.reify $ EV.reify l
    _ :< EC.Int i ->
      T.pack (show i)

showItems :: [T.Text] -> T.Text
showItems =
  T.intercalate " "

showPrim :: WP.WeakPrim WT.WeakTerm -> T.Text
showPrim prim =
  case prim of
    WP.Type t ->
      PT.toText t
    WP.Value primValue ->
      case primValue of
        WPV.Int _ v ->
          T.pack (show v)
        WPV.Float _ v ->
          T.pack (show v)
        WPV.Op (PO.PrimOp opName _ _) ->
          opName

showCons :: [T.Text] -> T.Text
showCons =
  inParen . T.intercalate " "

splitLast :: [a] -> Maybe ([a], a)
splitLast xs =
  if null xs
    then Nothing
    else Just (init xs, last xs)

showMatchArgs :: [(Ident, WT.WeakTerm)] -> T.Text
showMatchArgs xes = do
  showCons $ map showMatchArg xes

showMatchArg :: (Ident, WT.WeakTerm) -> T.Text
showMatchArg (x, e) = do
  showCons [showVariable x, toText e]

showDecisionTree :: DT.DecisionTree WT.WeakTerm -> T.Text
showDecisionTree tree =
  case tree of
    DT.Leaf xs cont ->
      showCons ["leaf", showCons (map showVariable xs), toText cont]
    DT.Unreachable ->
      "UNREACHABLE"
    DT.Switch (cursor, cursorType) (fallbackClause, clauseList) -> do
      showCons $
        "switch"
          : showCons [showCons [showVariable cursor, toText cursorType]]
          : showDecisionTree fallbackClause
          : map showClauseList clauseList

showClauseList :: DT.Case WT.WeakTerm -> T.Text
showClauseList (DT.Cons consName d dataArgs consArgs cont) = do
  showCons
    [ DD.reify consName,
      T.pack (show (D.reify d)),
      showCons $ map toText dataArgs,
      inParen $ showTypeArgs consArgs,
      showDecisionTree cont
    ]
