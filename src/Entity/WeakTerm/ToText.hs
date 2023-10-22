module Entity.WeakTerm.ToText (toText, showDecisionTree, showGlobalVariable) where

import Control.Comonad.Cofree
import Data.Text qualified as T
import Entity.Attr.Data qualified as AttrD
import Entity.Attr.DataIntro qualified as AttrDI
import Entity.Attr.VarGlobal qualified as AttrVG
import Entity.BaseName qualified as BN
import Entity.Binder
import Entity.DecisionTree qualified as DT
import Entity.DefiniteDescription qualified as DD
import Entity.Discriminant qualified as D
import Entity.Hint
import Entity.HoleID qualified as HID
import Entity.Ident
import Entity.Ident.Reify qualified as Ident
import Entity.LamKind qualified as LK
import Entity.LocalLocator qualified as LL
import Entity.PrimOp qualified as PO
import Entity.PrimType.ToText qualified as PT
import Entity.WeakPrim qualified as WP
import Entity.WeakPrimValue qualified as WPV
import Entity.WeakTerm qualified as WT

toText :: WT.WeakTerm -> T.Text
toText term =
  case term of
    _ :< WT.Tau ->
      "tau"
    _ :< WT.Var x ->
      showVariable x
    _ :< WT.VarGlobal _ x ->
      showGlobalVariable x
    _ :< WT.Pi xts cod ->
      showCons ["Π", inParen $ showTypeArgs xts, toText cod]
    _ :< WT.PiIntro kind xts e -> do
      case kind of
        LK.Fix (_, x, _) -> do
          let argStr = inParen $ showItems $ map showArg xts
          showCons ["fix", showVariable x, argStr, toText e]
        LK.Normal -> do
          let argStr = inParen $ showItems $ map showArg xts
          showCons ["λ", argStr, toText e]
    _ :< WT.PiElim e es ->
      case e of
        _ :< WT.VarGlobal attr _
          | AttrVG.isConstLike attr ->
              toText e
        _ ->
          showCons $ map toText $ e : es
    _ :< WT.Data (AttrD.Attr {..}) name es -> do
      if isConstLike
        then "{data}" <> showGlobalVariable name
        else showCons $ "{data}" <> showGlobalVariable name : map toText es
    _ :< WT.DataIntro (AttrDI.Attr {..}) consName _ consArgs -> do
      if isConstLike
        then "{data}" <> showGlobalVariable consName
        else showCons ("{data-intro}" <> showGlobalVariable consName : map toText consArgs)
    _ :< WT.DataElim isNoetic xets tree -> do
      if isNoetic
        then showCons ["match*", showMatchArgs xets, showDecisionTree tree]
        else showCons ["match", showMatchArgs xets, showDecisionTree tree]
    _ :< WT.Noema t ->
      showCons ["noema", toText t]
    _ :< WT.Embody _ e ->
      "*" <> toText e
    _ :< WT.Let opacity (_, x, t) e1 e2 -> do
      case opacity of
        WT.Transparent ->
          showCons ["let", showVariable x, toText t, toText e1, toText e2]
        _ ->
          showCons ["let-opaque", showVariable x, toText t, toText e1, toText e2]
    _ :< WT.Prim prim ->
      showPrim prim
    _ :< WT.Hole i es ->
      showCons $ "?M" <> T.pack (show (HID.reify i)) : map toText es
    _ :< WT.ResourceType name ->
      showGlobalVariable name
    _ :< WT.Magic m -> do
      let a = fmap toText m
      showCons [T.pack $ show a]
    _ :< WT.Annotation _ _ e ->
      toText e
    _ :< WT.Flow _ t -> do
      showCons ["flow", toText t]
    _ :< WT.FlowIntro _ _ (e, _) -> do
      showCons ["run", toText e]
    _ :< WT.FlowElim _ _ (e, _) -> do
      showCons ["wait", toText e]

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

showGlobalVariable :: DD.DefiniteDescription -> T.Text
showGlobalVariable dd =
  BN.reify $ LL.baseName $ DD.localLocator dd

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
        WPV.Int t v ->
          "{" <> toText t <> "}" <> T.pack (show v)
        WPV.Float _ v ->
          T.pack (show v)
        WPV.Op op ->
          case op of
            PO.PrimUnaryOp name _ _ ->
              showCons [T.pack (show name)]
            PO.PrimBinaryOp name _ _ ->
              showCons [T.pack (show name)]
            PO.PrimCmpOp name _ _ ->
              showCons [T.pack (show name)]
            PO.PrimConvOp name _ _ ->
              showCons [T.pack (show name)]
        WPV.StaticText _ text ->
          T.pack $ show text

showCons :: [T.Text] -> T.Text
showCons =
  inParen . T.intercalate " "

showMatchArgs :: [(Ident, WT.WeakTerm, WT.WeakTerm)] -> T.Text
showMatchArgs xets = do
  showCons $ map showMatchArg xets

showMatchArg :: (Ident, WT.WeakTerm, WT.WeakTerm) -> T.Text
showMatchArg (x, e, t) = do
  showCons [showVariable x, toText e, toText t]

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
showClauseList decisionCase = do
  showCons
    [ showGlobalVariable (DT.consDD decisionCase),
      T.pack (show (D.reify (DT.disc decisionCase))),
      showCons $ map (\(e, t) -> showCons [toText e, toText t]) (DT.dataArgs decisionCase),
      inParen $ showTypeArgs (DT.consArgs decisionCase),
      showDecisionTree (DT.cont decisionCase)
    ]
