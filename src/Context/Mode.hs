module Context.Mode where

import qualified Context.Alias as Alias
import qualified Context.CompDefinition as CompDefinition
import qualified Context.Definition as Definition
import qualified Context.Gensym as Gensym
import qualified Context.Global as Global
import qualified Context.Implicit as Implicit
import qualified Context.LLVM as LLVM
import qualified Context.Locator as Locator
import qualified Context.Log as Log
import qualified Context.Module as Module
import qualified Context.Path as Path
import qualified Context.Throw as Throw
import qualified Context.Type as Type

data Mode = Mode
  { logCtx :: Log.Config -> IO Log.Context,
    throwCtx :: Throw.Config -> IO Throw.Context,
    gensymCtx :: Gensym.Config -> IO Gensym.Context,
    llvmCtx :: LLVM.Config -> IO LLVM.Context,
    globalCtx :: Global.Config -> IO Global.Context,
    locatorCtx :: Locator.Config -> IO Locator.Context,
    aliasCtx :: Alias.Config -> IO Alias.Context,
    pathCtx :: Path.Config -> IO Path.Context,
    moduleCtx :: Module.Config -> IO Module.Context,
    typeCtx :: Type.Config -> IO Type.Context,
    implicitCtx :: Implicit.Config -> IO Implicit.Context,
    definitionCtx :: Definition.Config -> IO Definition.Context,
    compDefinitionCtx :: CompDefinition.Config -> IO CompDefinition.Context
  }
