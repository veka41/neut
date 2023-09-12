module Context.App.Internal where

import Data.ByteString.Builder
import Data.HashMap.Strict qualified as Map
import Data.IORef
import Data.IORef.Unboxed
import Data.IntMap qualified as IntMap
import Data.PQueue.Min qualified as Q
import Data.Set qualified as S
import Data.Text qualified as T
import Entity.AliasInfo
import Entity.ArgNum qualified as AN
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
import Entity.LocalLocator qualified as LL
import Entity.LocationTree qualified as LT
import Entity.LowType qualified as LT
import Entity.Macro qualified as Macro
import Entity.Module qualified as M
import Entity.Module qualified as Module
import Entity.ModuleAlias qualified as MA
import Entity.ModuleDigest qualified as MD
import Entity.NameDependenceMap
import Entity.Opacity qualified as O
import Entity.OptimizableData
import Entity.Remark qualified as Remark
import Entity.Source qualified as Source
import Entity.StrictGlobalLocator qualified as SGL
import Entity.Term qualified as TM
import Entity.TopNameMap
import Entity.ViaMap
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
    moduleAliasMap :: IORef (Map.HashMap MA.ModuleAlias MD.ModuleDigest),
    locatorAliasMap :: IORef (Map.HashMap GLA.GlobalLocatorAlias SGL.StrictGlobalLocator),
    sourceNameMap :: IORef (Map.HashMap (Path Abs File) TopNameMap),
    nameMap :: IORef (Map.HashMap DD.DefiniteDescription (Hint, GN.GlobalName)),
    nameDependenceMap :: IORef NameDependenceMap,
    activeViaMap :: IORef ViaMap,
    viaMap :: IORef (Map.HashMap (Path Abs File) ViaMap),
    macroRuleEnv :: IORef Macro.Rules,
    antecedentMap :: IORef (Map.HashMap MD.ModuleDigest M.Module),
    constraintEnv :: IORef [C.Constraint],
    remarkList :: IORef [Remark.Remark], -- per file
    globalRemarkList :: IORef [Remark.Remark],
    tagMap :: IORef LT.LocationTree,
    unusedVariableMap :: IORef (IntMap.IntMap (Hint, Ident)),
    usedVariableSet :: IORef (S.Set Int),
    holeSubst :: IORef HS.HoleSubst,
    sourceChildrenMap :: IORef (Map.HashMap (Path Abs File) [(Source.Source, [AliasInfo])]),
    traceSourceList :: IORef [Source.Source],
    weakTypeEnv :: IORef (IntMap.IntMap WT.WeakTerm),
    preHoleEnv :: IORef (IntMap.IntMap WT.WeakTerm),
    holeEnv :: IORef (IntMap.IntMap (WT.WeakTerm, WT.WeakTerm)),
    constraintQueue :: IORef (Q.MinQueue C.SuspendedConstraint),
    artifactMap :: IORef (Map.HashMap (Path Abs File) AR.ArtifactTime),
    visitEnv :: IORef (Map.HashMap (Path Abs File) VisitInfo),
    weakDefMap :: IORef (Map.HashMap DD.DefiniteDescription WT.WeakTerm),
    defMap :: IORef (Map.HashMap DD.DefiniteDescription ([BinderF TM.Term], TM.Term)),
    staticTextList :: IORef [(DD.DefiniteDescription, (Builder, Int))],
    compAuxEnv :: IORef (Map.HashMap DD.DefiniteDescription (O.Opacity, [Ident], Comp)),
    dataDefMap :: IORef (Map.HashMap DD.DefiniteDescription [(D.Discriminant, [BinderF TM.Term], [BinderF TM.Term])]),
    codataDefMap :: IORef (Map.HashMap DD.DefiniteDescription ((DD.DefiniteDescription, AN.ArgNum, AN.ArgNum), [DD.DefiniteDescription])),
    keyArgMap :: IORef (Map.HashMap DD.DefiniteDescription (IsConstLike, (AN.ArgNum, [Key]))),
    optDataMap :: IORef (Map.HashMap DD.DefiniteDescription OptimizableData),
    impArgEnv :: IORef (Map.HashMap DD.DefiniteDescription AN.ArgNum),
    declEnv :: IORef (Map.HashMap DN.DeclarationName ([LT.LowType], LT.LowType)),
    definedNameSet :: IORef (S.Set DD.DefiniteDescription),
    compEnv :: IORef (Map.HashMap DD.DefiniteDescription (O.Opacity, [Ident], Comp)),
    typeEnv :: IORef (Map.HashMap DD.DefiniteDescription WT.WeakTerm),
    activeGlobalLocatorList :: IORef [SGL.StrictGlobalLocator],
    activeDefiniteDescriptionList :: IORef (Map.HashMap LL.LocalLocator DD.DefiniteDescription),
    currentGlobalLocator :: Ref SGL.StrictGlobalLocator,
    currentSource :: Ref Source.Source,
    mainModule :: Ref Module.Module
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
  macroRuleEnv <- newIORef Map.empty
  tagMap <- newIORef LT.empty
  unusedVariableMap <- newIORef IntMap.empty
  usedVariableSet <- newIORef S.empty
  nameMap <- newIORef Map.empty
  nameDependenceMap <- newIORef Map.empty
  activeViaMap <- newIORef Map.empty
  viaMap <- newIORef Map.empty
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
  optDataMap <- newIORef Map.empty
  impArgEnv <- newIORef Map.empty
  declEnv <- newIORef Map.empty
  compEnv <- newIORef Map.empty
  typeEnv <- newIORef Map.empty
  activeGlobalLocatorList <- newIORef []
  activeDefiniteDescriptionList <- newIORef Map.empty
  currentGlobalLocator <- newRef
  currentSource <- newRef
  mainModule <- newRef
  return Env {..}
