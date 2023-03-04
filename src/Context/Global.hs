module Context.Global
  ( registerStmtDefine,
    registerStmtDefineResource,
    lookup,
    initialize,
  )
where

import Context.App
import Context.App.Internal
import Context.Enum qualified as Enum
import Context.Throw qualified as Throw
import Control.Monad
import Data.HashMap.Strict qualified as Map
import Entity.Arity
import Entity.Arity qualified as A
import Entity.Binder
import Entity.DefiniteDescription qualified as DD
import Entity.Discriminant qualified as D
import Entity.GlobalName
import Entity.GlobalName qualified as GN
import Entity.Hint
import Entity.Hint qualified as Hint
import Entity.PrimOp.FromText qualified as PrimOp
import Entity.PrimType.FromText qualified as PT
import Entity.Stmt as ST
import Prelude hiding (lookup)

type NameMap = Map.HashMap DD.DefiniteDescription GN.GlobalName

registerStmtDefine :: Hint -> ST.StmtKindF a -> DD.DefiniteDescription -> A.Arity -> App ()
registerStmtDefine m stmtKind name arity = do
  case stmtKind of
    ST.Normal _ ->
      registerTopLevelFunc m name arity
    ST.Data dataName dataArgs consInfoList -> do
      registerData m dataName dataArgs consInfoList
      registerAsEnumIfNecessary dataName dataArgs consInfoList
    ST.DataIntro {} ->
      return ()

registerAsEnumIfNecessary ::
  DD.DefiniteDescription ->
  [BinderF a] ->
  [(DD.DefiniteDescription, [BinderF a], D.Discriminant)] ->
  App ()
registerAsEnumIfNecessary dataName dataArgs consInfoList =
  when (hasNoArgs dataArgs consInfoList) $ do
    Enum.insert dataName
    mapM_ (Enum.insert . (\(consName, _, _) -> consName)) consInfoList

hasNoArgs :: [BinderF a] -> [(DD.DefiniteDescription, [BinderF a], D.Discriminant)] -> Bool
hasNoArgs dataArgs consInfoList =
  null dataArgs && null (concatMap (\(_, consArgs, _) -> consArgs) consInfoList)

registerTopLevelFunc :: Hint -> DD.DefiniteDescription -> Arity -> App ()
registerTopLevelFunc m topLevelName arity = do
  topNameMap <- readRef' nameMap
  ensureFreshness m topNameMap topLevelName
  modifyRef' nameMap $ Map.insert topLevelName $ GN.TopLevelFunc arity

registerData ::
  Hint ->
  DD.DefiniteDescription ->
  [BinderF a] ->
  [(DD.DefiniteDescription, [BinderF a], D.Discriminant)] ->
  App ()
registerData m dataName dataArgs consInfoList = do
  topNameMap <- readRef' nameMap
  ensureFreshness m topNameMap dataName
  let consList = map (\(consName, _, _) -> consName) consInfoList
  let dataArity = A.fromInt $ length dataArgs
  modifyRef' nameMap $ Map.insert dataName $ GN.Data dataArity consList
  forM_ consInfoList $ \(consName, consArgs, discriminant) -> do
    topNameMap' <- readRef' nameMap
    ensureFreshness m topNameMap' consName
    let consArity = A.fromInt $ length consArgs
    modifyRef' nameMap $ Map.insert consName $ GN.DataIntro dataArity consArity discriminant

registerStmtDefineResource :: Hint -> DD.DefiniteDescription -> App ()
registerStmtDefineResource m resourceName = do
  topNameMap <- readRef' nameMap
  ensureFreshness m topNameMap resourceName
  modifyRef' nameMap $ Map.insert resourceName GN.Resource

lookup :: DD.DefiniteDescription -> App (Maybe GlobalName)
lookup name = do
  nameMap <- readRef' nameMap
  case Map.lookup name nameMap of
    Just kind ->
      return $ Just kind
    Nothing
      | Just primType <- PT.fromDefiniteDescription name ->
          return $ Just $ GN.PrimType primType
      | Just primOp <- PrimOp.fromDefiniteDescription name ->
          return $ Just $ GN.PrimOp primOp
      | otherwise -> do
          return Nothing

initialize :: App ()
initialize = do
  writeRef' nameMap Map.empty

ensureFreshness :: Hint.Hint -> NameMap -> DD.DefiniteDescription -> App ()
ensureFreshness m topNameMap name = do
  when (Map.member name topNameMap) $
    Throw.raiseError m $
      "`" <> DD.reify name <> "` is already defined"
