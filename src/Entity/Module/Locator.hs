module Entity.Module.Locator (getNextModule) where

import Control.Exception.Safe
import Control.Monad
import Control.Monad.IO.Class
import qualified Data.HashMap.Lazy as Map
import Data.IORef
import qualified Data.Text as T
import Entity.Global
import Entity.Hint
import Entity.Log
import Entity.Module
import qualified Entity.Module.Reflect as Module
import Entity.ModuleAlias
import Entity.ModuleChecksum
import Path
import Path.IO
import System.IO.Unsafe

getNextModule :: Hint -> Module -> ModuleAlias -> IO Module
getNextModule m currentModule nextModuleAlias = do
  nextModuleFilePath <- getNextModuleFilePath m currentModule nextModuleAlias
  moduleCacheMap <- liftIO $ readIORef moduleCacheMapRef
  case Map.lookup nextModuleFilePath moduleCacheMap of
    Just nextModule ->
      return nextModule
    Nothing -> do
      moduleFileExists <- doesFileExist nextModuleFilePath
      unless moduleFileExists $ do
        raiseError m $
          T.pack "could not find the module file for `"
            <> extract nextModuleAlias
            <> "`"
      nextModule <- Module.fromFilePath nextModuleFilePath
      modifyIORef' moduleCacheMapRef $ Map.insert nextModuleFilePath nextModule
      return nextModule

getNextModuleFilePath :: Hint -> Module -> ModuleAlias -> IO (Path Abs File)
getNextModuleFilePath m currentModule nextModuleAlias = do
  moduleDirPath <- getNextModuleDirPath m currentModule nextModuleAlias
  return $ moduleDirPath </> moduleFile

getNextModuleDirPath :: Hint -> Module -> ModuleAlias -> IO (Path Abs Dir)
getNextModuleDirPath m currentModule nextModuleAlias =
  if nextModuleAlias == ModuleAlias defaultModulePrefix
    then getCurrentFilePath >>= filePathToModuleFileDir
    else do
      ModuleChecksum checksum <- resolveModuleAliasIntoModuleName m currentModule nextModuleAlias
      libraryDir <- getLibraryDirPath
      resolveDir libraryDir $ T.unpack checksum

{-# NOINLINE moduleCacheMapRef #-}
moduleCacheMapRef :: IORef (Map.HashMap (Path Abs File) Module)
moduleCacheMapRef =
  unsafePerformIO (newIORef Map.empty)

filePathToModuleFilePath :: Path Abs File -> IO (Path Abs File)
filePathToModuleFilePath filePath = do
  findModuleFile $ parent filePath

filePathToModuleFileDir :: Path Abs File -> IO (Path Abs Dir)
filePathToModuleFileDir filePath =
  parent <$> filePathToModuleFilePath filePath

resolveModuleAliasIntoModuleName :: MonadThrow m => Hint -> Module -> ModuleAlias -> m ModuleChecksum
resolveModuleAliasIntoModuleName m currentModule (ModuleAlias nextModuleAlias) =
  case Map.lookup nextModuleAlias (moduleDependency currentModule) of
    Just (_, checksum) ->
      return checksum
    Nothing ->
      raiseError m $ "no such module alias is defined: " <> nextModuleAlias

-- getNextSource :: Hint -> Module -> ModuleAlias -> IO Source
-- getNextSource m currentModule nextModuleAlias = do
--   -- sig@(nextModuleName, _, _) <- parseModuleInfo m sigText
--   newModule <- getNextModule m currentModule nextModuleAlias
--   filePath <- getSourceFilePath newModule sig
--   return $
--     Source
--       { sourceModule = newModule,
--         sourceFilePath = filePath
--       }

-- getSourceFilePath :: Module -> SourceSignature -> IO (Path Abs File)
-- getSourceFilePath baseModule (_, locator, name) = do
--   resolveFile (getSourceDir baseModule) (sectionToPath $ locator ++ [name])

-- sourceSignatureは、(ModuleAlias, [DirPath], FileName) になってるのか。
-- sectionToPath :: [T.Text] -> FilePath
-- sectionToPath sectionPath =
--   T.unpack $ T.intercalate (T.singleton FP.pathSeparator) sectionPath <> "." <> sourceFileExtension
