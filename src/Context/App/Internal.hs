module Context.App.Internal where

import Data.HashMap.Strict qualified as Map
import Data.IORef
import Data.IORef.Unboxed
import Data.IntMap qualified as IntMap
import Data.PQueue.Min qualified as Q
import Data.Set qualified as S
import Data.Text qualified as T
import Entity.AliasInfo
import Entity.ArgNum qualified as AN
import Entity.Arity qualified as A
import Entity.Artifact qualified as AR
import Entity.Binder
import Entity.BuildMode qualified as BM
import Entity.Comp
import Entity.Constraint qualified as C
import Entity.DeclarationName qualified as DN
import Entity.DefiniteDescription qualified as DD
import Entity.Discriminant qualified as D
import Entity.GlobalLocatorAlias qualified as GLA
import Entity.GlobalName qualified as GN
import Entity.Hint
import Entity.HoleSubst qualified as HS
import Entity.Ident
import Entity.IsConstLike
import Entity.Key
import Entity.LocationTree qualified as LT
import Entity.LowType qualified as LT
import Entity.Module qualified as M
import Entity.Module qualified as Module
import Entity.ModuleAlias qualified as MA
import Entity.ModuleChecksum qualified as MC
import Entity.Opacity qualified as O
import Entity.Remark qualified as Remark
import Entity.Source qualified as Source
import Entity.StrictGlobalLocator qualified as SGL
import Entity.TargetPlatform qualified as TP
import Entity.Term qualified as TM
import Entity.TopNameMap
import Entity.VisitInfo
import Entity.WeakTerm qualified as WT
import Path

data Env = Env
  { counter :: IORefU Int,
    endOfEntry :: IORef T.Text,
    clangOptString :: IORef String,
    shouldColorize :: IORef Bool,
    buildMode :: IORef BM.BuildMode,
    moduleCacheMap :: IORef (Map.HashMap (Path Abs File) M.Module),
    moduleAliasMap :: IORef (Map.HashMap MA.ModuleAlias MC.ModuleChecksum),
    locatorAliasMap :: IORef (Map.HashMap GLA.GlobalLocatorAlias [SGL.StrictGlobalLocator]),
    sourceNameMap :: IORef (Map.HashMap (Path Abs File) TopNameMap),
    nameMap :: IORef (Map.HashMap DD.DefiniteDescription (Hint, GN.GlobalName)),
    localNameMap :: IORef (Map.HashMap DD.DefiniteDescription (Hint, GN.GlobalName)),
    antecedentMap :: IORef (Map.HashMap MC.ModuleChecksum M.Module),
    constraintEnv :: IORef [C.Constraint],
    remarkList :: IORef [Remark.Remark], -- per file
    globalRemarkList :: IORef [Remark.Remark],
    tagMap :: IORef LT.LocationTree,
    unusedVariableMap :: IORef (IntMap.IntMap (Hint, Ident)),
    usedVariableSet :: IORef (S.Set Int),
    holeSubst :: IORef HS.HoleSubst,
    sourceChildrenMap :: IORef (Map.HashMap (Path Abs File) [(Source.Source, AliasInfo)]),
    traceSourceList :: IORef [Source.Source],
    weakTypeEnv :: IORef (IntMap.IntMap WT.WeakTerm),
    preHoleEnv :: IORef (IntMap.IntMap WT.WeakTerm),
    holeEnv :: IORef (IntMap.IntMap (WT.WeakTerm, WT.WeakTerm)),
    constraintQueue :: IORef (Q.MinQueue C.SuspendedConstraint),
    artifactMap :: IORef (Map.HashMap (Path Abs File) AR.ArtifactTime),
    visitEnv :: IORef (Map.HashMap (Path Abs File) VisitInfo),
    weakDefMap :: IORef (Map.HashMap DD.DefiniteDescription WT.WeakTerm),
    defMap :: IORef (Map.HashMap DD.DefiniteDescription TM.Term),
    staticTextList :: IORef [(DD.DefiniteDescription, (T.Text, Int))],
    compAuxEnv :: IORef (Map.HashMap DD.DefiniteDescription (O.Opacity, [Ident], Comp)),
    dataDefMap :: IORef (Map.HashMap DD.DefiniteDescription [(D.Discriminant, [BinderF TM.Term], [BinderF TM.Term])]),
    codataDefMap :: IORef (Map.HashMap DD.DefiniteDescription ((DD.DefiniteDescription, A.Arity, A.Arity), [DD.DefiniteDescription])),
    keyArgMap :: IORef (Map.HashMap DD.DefiniteDescription (IsConstLike, (A.Arity, [Key]))),
    enumSet :: IORef (S.Set DD.DefiniteDescription),
    impArgEnv :: IORef (Map.HashMap DD.DefiniteDescription AN.ArgNum),
    declEnv :: IORef (Map.HashMap DN.DeclarationName ([LT.LowType], LT.LowType)),
    extEnv :: IORef (S.Set DD.DefiniteDescription),
    definedNameSet :: IORef (S.Set DD.DefiniteDescription),
    compEnv :: IORef (Map.HashMap DD.DefiniteDescription (O.Opacity, [Ident], Comp)),
    typeEnv :: IORef (Map.HashMap DD.DefiniteDescription WT.WeakTerm),
    activeGlobalLocatorList :: IORef [SGL.StrictGlobalLocator],
    currentGlobalLocator :: Ref SGL.StrictGlobalLocator,
    currentSource :: Ref Source.Source,
    mainModule :: Ref Module.Module,
    targetPlatform :: Ref TP.TargetPlatform
  }

type Ref a = IORef (Maybe a)

newRef :: IO (Ref a)
newRef =
  newIORef Nothing

newEnv :: IO Env
newEnv = do
  counter <- newIORefU 0
  endOfEntry <- newIORef ""
  clangOptString <- newIORef ""
  shouldColorize <- newIORef True
  buildMode <- newIORef BM.Develop
  moduleCacheMap <- newIORef Map.empty
  moduleAliasMap <- newIORef Map.empty
  locatorAliasMap <- newIORef Map.empty
  sourceNameMap <- newIORef Map.empty
  remarkList <- newIORef []
  globalRemarkList <- newIORef []
  tagMap <- newIORef LT.empty
  unusedVariableMap <- newIORef IntMap.empty
  usedVariableSet <- newIORef S.empty
  nameMap <- newIORef Map.empty
  localNameMap <- newIORef Map.empty
  antecedentMap <- newIORef Map.empty
  constraintEnv <- newIORef []
  holeSubst <- newIORef HS.empty
  sourceChildrenMap <- newIORef Map.empty
  weakTypeEnv <- newIORef IntMap.empty
  preHoleEnv <- newIORef IntMap.empty
  holeEnv <- newIORef IntMap.empty
  constraintQueue <- newIORef Q.empty
  traceSourceList <- newIORef []
  artifactMap <- newIORef Map.empty
  definedNameSet <- newIORef S.empty
  visitEnv <- newIORef Map.empty
  weakDefMap <- newIORef Map.empty
  defMap <- newIORef Map.empty
  staticTextList <- newIORef []
  compAuxEnv <- newIORef Map.empty
  dataDefMap <- newIORef Map.empty
  codataDefMap <- newIORef Map.empty
  keyArgMap <- newIORef Map.empty
  enumSet <- newIORef S.empty
  impArgEnv <- newIORef Map.empty
  declEnv <- newIORef Map.empty
  extEnv <- newIORef S.empty
  compEnv <- newIORef Map.empty
  typeEnv <- newIORef Map.empty
  activeGlobalLocatorList <- newIORef []
  currentGlobalLocator <- newRef
  currentSource <- newRef
  mainModule <- newRef
  targetPlatform <- newRef
  return Env {..}
