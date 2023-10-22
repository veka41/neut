module Scene.Term.Subst (subst, subst'', substDecisionTree) where

import Context.App
import Context.Gensym qualified as Gensym
import Control.Comonad.Cofree
import Data.IntMap qualified as IntMap
import Data.Maybe (mapMaybe)
import Entity.Binder
import Entity.DecisionTree qualified as DT
import Entity.Ident
import Entity.Ident.Reify qualified as Ident
import Entity.LamKind qualified as LK
import Entity.Term qualified as TM

type SubstTerm =
  IntMap.IntMap (Either Ident TM.Term)

subst :: SubstTerm -> TM.Term -> App TM.Term
subst sub term =
  case term of
    (_ :< TM.Tau) ->
      return term
    (m :< TM.Var x)
      | Just varOrTerm <- IntMap.lookup (Ident.toInt x) sub ->
          case varOrTerm of
            Left x' ->
              return $ m :< TM.Var x'
            Right e ->
              return e
      | otherwise ->
          return term
    (_ :< TM.VarGlobal {}) ->
      return term
    (m :< TM.Pi xts t) -> do
      (xts', t') <- subst' sub xts t
      return (m :< TM.Pi xts' t')
    (m :< TM.PiIntro kind xts e) -> do
      case kind of
        LK.Fix xt -> do
          (xt' : xts', e') <- subst' sub (xt : xts) e
          return (m :< TM.PiIntro (LK.Fix xt') xts' e')
        _ -> do
          (xts', e') <- subst' sub xts e
          return (m :< TM.PiIntro kind xts' e')
    (m :< TM.PiElim e es) -> do
      e' <- subst sub e
      es' <- mapM (subst sub) es
      return (m :< TM.PiElim e' es')
    m :< TM.Data attr name es -> do
      es' <- mapM (subst sub) es
      return $ m :< TM.Data attr name es'
    m :< TM.DataIntro attr consName dataArgs consArgs -> do
      dataArgs' <- mapM (subst sub) dataArgs
      consArgs' <- mapM (subst sub) consArgs
      return $ m :< TM.DataIntro attr consName dataArgs' consArgs'
    m :< TM.DataElim isNoetic oets decisionTree -> do
      let (os, es, ts) = unzip3 oets
      es' <- mapM (subst sub) es
      let binder = zipWith (\o t -> (m, o, t)) os ts
      (binder', decisionTree') <- subst'' sub binder decisionTree
      let (_, os', ts') = unzip3 binder'
      return $ m :< TM.DataElim isNoetic (zip3 os' es' ts') decisionTree'
    m :< TM.Noema t -> do
      t' <- subst sub t
      return $ m :< TM.Noema t'
    m :< TM.Embody t e -> do
      t' <- subst sub t
      e' <- subst sub e
      return $ m :< TM.Embody t' e'
    m :< TM.Let opacity mxt e1 e2 -> do
      e1' <- subst sub e1
      ([mxt'], e2') <- subst' sub [mxt] e2
      return $ m :< TM.Let opacity mxt' e1' e2'
    _ :< TM.ResourceType {} ->
      return term
    _ :< TM.Prim _ ->
      return term
    m :< TM.Magic der -> do
      der' <- traverse (subst sub) der
      return (m :< TM.Magic der')
    m :< TM.Flow pVar t -> do
      t' <- subst sub t
      return $ m :< TM.Flow pVar t'
    m :< TM.FlowIntro pVar var (e, t) -> do
      e' <- subst sub e
      t' <- subst sub t
      return $ m :< TM.FlowIntro pVar var (e', t')
    m :< TM.FlowElim pVar var (e, t) -> do
      e' <- subst sub e
      t' <- subst sub t
      return $ m :< TM.FlowElim pVar var (e', t')

subst' ::
  SubstTerm ->
  [BinderF TM.Term] ->
  TM.Term ->
  App ([BinderF TM.Term], TM.Term)
subst' sub binder e =
  case binder of
    [] -> do
      e' <- subst sub e
      return ([], e')
    ((m, x, t) : xts) -> do
      t' <- subst sub t
      x' <- Gensym.newIdentFromIdent x
      let sub' = IntMap.insert (Ident.toInt x) (Left x') sub
      (xts', e') <- subst' sub' xts e
      return ((m, x', t') : xts', e')

subst'' ::
  SubstTerm ->
  [BinderF TM.Term] ->
  DT.DecisionTree TM.Term ->
  App ([BinderF TM.Term], DT.DecisionTree TM.Term)
subst'' sub binder decisionTree =
  case binder of
    [] -> do
      decisionTree' <- substDecisionTree sub decisionTree
      return ([], decisionTree')
    ((m, x, t) : xts) -> do
      t' <- subst sub t
      x' <- Gensym.newIdentFromIdent x
      let sub' = IntMap.insert (Ident.toInt x) (Left x') sub
      (xts', e') <- subst'' sub' xts decisionTree
      return ((m, x', t') : xts', e')

substDecisionTree ::
  SubstTerm ->
  DT.DecisionTree TM.Term ->
  App (DT.DecisionTree TM.Term)
substDecisionTree sub tree =
  case tree of
    DT.Leaf xs e -> do
      e' <- subst sub e
      let xs' = mapMaybe (substLeafVar sub) xs
      return $ DT.Leaf xs' e'
    DT.Unreachable ->
      return tree
    DT.Switch (cursorVar, cursor) caseList -> do
      let cursorVar' = substVar sub cursorVar
      cursor' <- subst sub cursor
      caseList' <- substCaseList sub caseList
      return $ DT.Switch (cursorVar', cursor') caseList'

substCaseList ::
  SubstTerm ->
  DT.CaseList TM.Term ->
  App (DT.CaseList TM.Term)
substCaseList sub (fallbackClause, clauseList) = do
  fallbackClause' <- substDecisionTree sub fallbackClause
  clauseList' <- mapM (substCase sub) clauseList
  return (fallbackClause', clauseList')

substCase ::
  SubstTerm ->
  DT.Case TM.Term ->
  App (DT.Case TM.Term)
substCase sub decisionCase = do
  let (dataTerms, dataTypes) = unzip $ DT.dataArgs decisionCase
  dataTerms' <- mapM (subst sub) dataTerms
  dataTypes' <- mapM (subst sub) dataTypes
  (consArgs', cont') <- subst'' sub (DT.consArgs decisionCase) (DT.cont decisionCase)
  return $
    decisionCase
      { DT.dataArgs = zip dataTerms' dataTypes',
        DT.consArgs = consArgs',
        DT.cont = cont'
      }

substLeafVar :: SubstTerm -> Ident -> Maybe Ident
substLeafVar sub leafVar =
  case IntMap.lookup (Ident.toInt leafVar) sub of
    Just (Left leafVar') ->
      return leafVar'
    Just (Right _) ->
      Nothing
    Nothing ->
      return leafVar

substVar :: SubstTerm -> Ident -> Ident
substVar sub x =
  case IntMap.lookup (Ident.toInt x) sub of
    Just (Left x') ->
      x'
    _ ->
      x
