module Context.App.Main
  (
  )
where

-- import Context.App
-- import qualified Context.Enum.Main as Enum
-- import qualified Context.Gensym.Main as Gensym
-- import qualified Context.Global.Main as Global
-- import qualified Context.LLVM.Main as LLVM
-- import qualified Context.Locator.Main as Locator
-- import qualified Context.Log.IO as Log
-- import qualified Context.Throw.IO as Throw
-- import qualified Data.Text as T
-- import Path
-- import Prelude hiding (log)

-- newtype Config = Config
--   { mainFilePathConf :: Path Abs File
--   }

-- new :: Log.Config -> Throw.Config -> String -> IO Axis
-- new logCfg throwCfg clangOptStr = do
--   logCtx <- Log.new logCfg
--   throwCtx <- Throw.new throwCfg
--   gensymCtx <- Gensym.new
--   llvmCtx <- LLVM.new clangOptStr throwCtx
--   enumCtx <- Enum.new throwCtx
--   globalCtx <- Global.new throwCtx
--   locatorCtx <- Locator.new
--   return
--     Axis
--       { log = logCtx,
--         throw = throwCtx,
--         gensym = gensymCtx,
--         llvm = llvmCtx,
--         enum = enumCtx,
--         global = globalCtx,
--         locator = locatorCtx
--       }

-- new1 :: Log.Config -> Throw.Config -> String -> IO (T.Text -> IO Axis)
-- new1 logCfg throwCfg clangOptStr = do
--   logCtx <- Log.new logCfg
--   throwCtx <- Throw.new throwCfg
--   gensymCtx <- Gensym.new
--   llvmCtx <- LLVM.new clangOptStr throwCtx
--   enumCtx <- Enum.new throwCtx
--   globalCtx <- Global.new throwCtx
--   return $ \globalLocator -> do
--     locatorCtx <- Locator.new throwCtx globalLocator
--     return
--       Axis
--         { log = logCtx,
--           throw = throwCtx,
--           gensym = gensymCtx,
--           llvm = llvmCtx,
--           enum = enumCtx,
--           global = globalCtx,
--           locator = locatorCtx
--         }