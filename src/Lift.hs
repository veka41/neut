module Lift where

import           Control.Comonad.Cofree
import           Control.Monad
import           Control.Monad.State        hiding (lift)
import           Control.Monad.Trans.Except

import           Data

lift :: Term -> WithEnv Term
lift v@(_ :< TermVar _) = return v
lift (i :< TermThunk c) = do
  c' <- lift c
  return $ i :< TermThunk c'
lift (i :< TermLam arg body) = do
  lamPol <- lookupPolEnv' i
  body' <- lift body
  let freeVars = var body'
  newFormalArgs <- constructFormalArgs lamPol freeVars
  let f2b = zip freeVars (map argToTerm newFormalArgs)
  body'' <- replace f2b body'
  lam' <- lamSeq newFormalArgs $ i :< TermLam arg body''
  args <- wrapArg $ zip freeVars newFormalArgs
  appFold lam' args
lift (i :< TermApp e v) = do
  e' <- lift e
  v' <- lift v
  return $ i :< TermApp e' v'
lift (i :< TermLift v) = do
  v' <- lift v
  return $ i :< TermLift v'
lift (i :< TermColift v) = do
  v' <- lift v
  return $ i :< TermColift v'
lift (i :< TermUnthunk v) = do
  v' <- lift v
  return $ i :< TermUnthunk v'
lift (meta :< TermMu s c) = do
  c' <- lift c
  return $ meta :< TermMu s c'
lift (i :< TermCase vs vcs) = do
  vs' <- mapM lift vs
  let (patList, bodyList) = unzip vcs
  bodyList' <- mapM lift bodyList
  return $ i :< TermCase vs' (zip patList bodyList')
lift _ = error "Lift.lift: illegal argument"

type VIdentifier = (Identifier, Identifier)

replace :: [(Identifier, Term)] -> Term -> WithEnv Term
replace f2b (i :< TermVar s) = do
  case lookup s f2b of
    Nothing   -> return $ i :< TermVar s
    Just term -> return term
replace args (i :< TermThunk c) = do
  c' <- replace args c
  return $ i :< TermThunk c'
replace args (i :< TermLam x e) = do
  e' <- replace args e
  return $ i :< TermLam x e'
replace args (i :< TermApp e v) = do
  e' <- replace args e
  v' <- replace args v
  return $ i :< TermApp e' v'
replace args (i :< TermLift v) = do
  v' <- replace args v
  return $ i :< TermLift v'
replace args (i :< TermColift v) = do
  v' <- replace args v
  return $ i :< TermColift v'
replace args (i :< TermUnthunk v) = do
  v' <- replace args v
  return $ i :< TermUnthunk v'
replace args (i :< TermMu s c) = do
  c' <- replace args c
  return $ i :< TermMu s c'
replace args (i :< TermCase vs vcs) = do
  vs' <- mapM (replace args) vs
  let (patList, bodyList) = unzip vcs
  bodyList' <- mapM (replace args) bodyList
  return $ i :< TermCase vs' (zip patList bodyList')
replace _ _ = error "Lift.replace: illegal argument"

var :: Term -> [Identifier]
var (_ :< TermVar s) = [s]
var (_ :< TermThunk e) = var e
var (_ :< TermLam s e) = filter (\t -> t /= varArg s) $ var e
var (_ :< TermApp e v) = var e ++ var v
var (_ :< TermLift v) = var v
var (_ :< TermColift v) = var v
var (_ :< TermUnthunk v) = var v
var (_ :< TermMu s e) = filter (\t -> t /= varArg s) (var e)
var (_ :< TermCase vs vses) = do
  let efs = join $ map var vs
  let (patList, bodyList) = unzip vses
  let vs1 = join $ join $ map (map varPat) patList
  let vs2 = join $ map var bodyList
  efs ++ vs1 ++ vs2
var _ = error "Lift.var: illegal argument"

varPat :: Pat -> [Identifier]
varPat (_ :< PatHole)     = []
varPat (_ :< PatVar s)    = [s]
varPat (_ :< PatApp _ ps) = join $ map varPat ps

varArg :: Arg -> Identifier
varArg (_ :< ArgIdent x)    = x
varArg (_ :< ArgLift arg)   = varArg arg
varArg (_ :< ArgColift arg) = varArg arg
varArg _                    = error "Lift.varArg: illegal argument"

constructFormalArgs :: Polarity -> [Identifier] -> WithEnv [Arg]
constructFormalArgs _ [] = return []
constructFormalArgs lamPol (ident:is) = do
  varType <- lookupTypeEnv' ident
  varPol <- lookupPolEnv' ident
  formalArg <- newNameWith "arg"
  insTypeEnv formalArg varType
  insPolEnv formalArg varPol
  varMeta <- newNameWith "meta"
  insTypeEnv varMeta varType
  insPolEnv varMeta varPol
  args <- constructFormalArgs lamPol is
  case (lamPol, varPol) of
    (PolarityPositive, PolarityPositive) -> do
      return $ (varMeta :< ArgIdent formalArg) : args
    (PolarityNegative, PolarityNegative) -> do
      return $ (varMeta :< ArgIdent formalArg) : args
    (PolarityPositive, PolarityNegative) -> do
      varMetaColift <- newNameWith "meta"
      insTypeEnv varMetaColift $ Fix (TypeDown varType)
      insPolEnv varMetaColift PolarityPositive
      return $
        (varMetaColift :< ArgColift (varMeta :< ArgIdent formalArg)) : args
    (PolarityNegative, PolarityPositive) -> do
      varMetaLift <- newNameWith "meta"
      insTypeEnv varMetaLift $ Fix (TypeUp varType)
      insPolEnv varMetaLift PolarityNegative
      return $ (varMetaLift :< ArgLift (varMeta :< ArgIdent formalArg)) : args
    _ -> error "lift.TermLam"

argToTerm :: Arg -> Term
argToTerm (meta :< ArgIdent x) = meta :< TermVar x
argToTerm (meta :< ArgLift arg) = do
  let term = argToTerm arg
  meta :< TermLift term
argToTerm (meta :< ArgColift arg) = do
  let term = argToTerm arg
  meta :< TermColift term
argToTerm _ = error "Lift.argToTerm: illegal argument"

lamSeq :: [Arg] -> Term -> WithEnv Term
lamSeq [] terminal = return terminal
lamSeq (arg@(metaArg :< _):xs) c@(metaLam :< _) = do
  tLam <- lookupTypeEnv' metaLam
  polLam <- lookupPolEnv' metaLam
  tArg <- lookupTypeEnv' metaArg
  tmp <- lamSeq xs c
  meta <- newNameWith "meta"
  insTypeEnv meta (Fix (TypeForall (arg, tArg) tLam))
  insPolEnv meta polLam
  return $ meta :< TermLam arg tmp

wrapArg :: [(Identifier, Arg)] -> WithEnv [Term]
wrapArg [] = return []
wrapArg ((i, _ :< ArgIdent _):rest) = do
  xs <- wrapArg rest
  t <- lookupTypeEnv' i
  pol <- lookupPolEnv' i
  meta <- newNameWith "meta"
  insTypeEnv meta t
  insPolEnv meta pol
  return $ (meta :< TermVar i) : xs
wrapArg ((i, _ :< ArgLift _):rest) = do
  termList <- wrapArg rest
  t <- lookupTypeEnv' i
  pol <- lookupPolEnv' i
  meta <- newNameWith "meta"
  insTypeEnv meta t
  insPolEnv meta pol
  metaLift <- newNameWith "meta"
  insTypeEnv metaLift (Fix (TypeUp t))
  insPolEnv metaLift PolarityNegative
  return $ (metaLift :< TermLift (meta :< TermVar i)) : termList
wrapArg ((i, _ :< ArgColift _):rest) = do
  termList <- wrapArg rest
  t <- lookupTypeEnv' i
  pol <- lookupPolEnv' i
  meta <- newNameWith "meta"
  insTypeEnv meta t
  insPolEnv meta pol
  metaColift <- newNameWith "meta"
  insTypeEnv metaColift (Fix (TypeDown t))
  insPolEnv metaColift PolarityPositive
  return $ (metaColift :< TermColift (meta :< TermVar i)) : termList
wrapArg _ = error "Lift.argToTerm: illegal argument"

appFold :: Term -> [Term] -> WithEnv Term
appFold e [] = return e
appFold e@(i :< _) (term:ts) = do
  t <- lookupTypeEnv' i
  pol <- lookupPolEnv' i
  case t of
    Fix (TypeForall _ tcod) -> do
      meta <- newNameWith "meta"
      insTypeEnv meta tcod
      insPolEnv meta pol
      appFold (meta :< TermApp e term) ts
    _ -> error "Lift.appFold"
