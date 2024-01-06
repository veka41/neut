{-# LANGUAGE TemplateHaskell #-}

module Context.Path
  ( getLibraryDirPath,
    getCurrentDir,
    ensureNotInLibDir,
    inLibDir,
    resolveDir,
    resolveFile,
    doesDirExist,
    doesFileExist,
    getModificationTime,
    setModificationTime,
    ensureDir,
    stripPrefix,
    writeByteString,
    writeText,
    getBaseName,
    parseRelFile,
    removeDirRecur,
    getExecutableOutputPath,
    getBaseBuildDir,
    getInstallDir,
    writeBuildSignature,
    getPlatformPrefix,
    sourceToOutputPath,
    getSourceCachePath,
    attachOutputPath,
  )
where

import Context.Antecedent qualified as Antecedent
import Context.App
import Context.App.Internal
import Context.Env qualified as Env
import Context.Parse (writeTextFile)
import Context.Throw qualified as Throw
import Control.Comonad.Cofree
import Control.Monad
import Control.Monad.IO.Class
import Data.Bifunctor
import Data.ByteString qualified as B
import Data.ByteString.Lazy qualified as L
import Data.ByteString.UTF8 qualified as B
import Data.HashMap.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text qualified as T
import Data.Text.Encoding
import Data.Time
import Data.Version qualified as V
import Entity.BuildMode qualified as BM
import Entity.Const
import Entity.Digest
import Entity.Ens qualified as E
import Entity.Ens.Reify qualified as E
import Entity.Module
import Entity.ModuleAlias qualified as MA
import Entity.ModuleID qualified as MID
import Entity.OutputKind qualified as OK
import Entity.Platform as TP
import Entity.Source qualified as Src
import Entity.Target qualified as Target
import Path (Abs, Dir, File, Path, Rel, (</>))
import Path qualified as P
import Path.IO qualified as P
import Paths_neut
import System.Environment

getLibraryDirPath :: App (Path Abs Dir)
getLibraryDirPath = do
  cacheDirPath <- getCacheDirPath
  returnDirectory $ cacheDirPath </> $(P.mkRelDir "library")

getCurrentDir :: App (Path Abs Dir)
getCurrentDir =
  P.getCurrentDir

ensureNotInLibDir :: App ()
ensureNotInLibDir = do
  b <- inLibDir
  when b $
    Throw.raiseError'
      "this command cannot be used under the library directory"

inLibDir :: App Bool
inLibDir = do
  currentDir <- getCurrentDir
  libDir <- getLibraryDirPath
  return $ P.isProperPrefixOf libDir currentDir

resolveDir :: Path Abs Dir -> FilePath -> App (Path Abs Dir)
resolveDir =
  P.resolveDir

resolveFile :: Path Abs Dir -> FilePath -> App (Path Abs File)
resolveFile =
  P.resolveFile

doesDirExist :: Path Abs Dir -> App Bool
doesDirExist =
  P.doesDirExist

doesFileExist :: Path Abs File -> App Bool
doesFileExist =
  P.doesFileExist

getModificationTime :: Path Abs File -> App UTCTime
getModificationTime =
  P.getModificationTime

setModificationTime :: Path Abs File -> UTCTime -> App ()
setModificationTime =
  P.setModificationTime

ensureDir :: Path Abs Dir -> App ()
ensureDir =
  P.ensureDir

getBaseName :: Path Abs File -> App T.Text
getBaseName path = do
  let dirPath = P.parent path
  filename <- P.stripProperPrefix dirPath path
  return $ T.replace packageFileExtension "" $ T.pack $ P.toFilePath filename

stripPrefix :: Path b Dir -> Path b t -> App (Path Rel t)
stripPrefix =
  P.stripProperPrefix

writeByteString :: Path Abs File -> L.ByteString -> App ()
writeByteString path content =
  liftIO $ L.writeFile (P.toFilePath path) content

writeText :: Path Abs File -> T.Text -> App ()
writeText path text =
  liftIO $ B.writeFile (P.toFilePath path) $ encodeUtf8 text

parseRelFile :: FilePath -> App (Path Rel File)
parseRelFile =
  P.parseRelFile

removeDirRecur :: Path Abs Dir -> App ()
removeDirRecur =
  P.removeDirRecur

getCacheDirPath :: App (Path Abs Dir)
getCacheDirPath = do
  mCacheDirPathString <- liftIO $ lookupEnv envVarCacheDir
  case mCacheDirPathString of
    Just cacheDirPathString -> do
      P.parseAbsDir cacheDirPathString >>= returnDirectory
    Nothing ->
      P.getXdgDir P.XdgCache (Just $(P.mkRelDir "neut")) >>= returnDirectory

returnDirectory :: Path Abs Dir -> App (Path Abs Dir)
returnDirectory path =
  P.ensureDir path >> return path

getPlatformPrefix :: App (Path Rel Dir)
getPlatformPrefix = do
  P.parseRelDir $ T.unpack $ TP.reify platform

getExecutableOutputPath :: Target.Target -> Module -> App (Path Abs File)
getExecutableOutputPath target mainModule = do
  executableDir <- getExecutableDir mainModule
  resolveFile executableDir $ T.unpack $ Target.extract target

getBaseBuildDir :: Module -> App (Path Abs Dir)
getBaseBuildDir baseModule = do
  platformPrefix <- getPlatformPrefix
  versionDir <- P.parseRelDir $ "compiler-" ++ V.showVersion version
  let moduleRootDir = getModuleRootDir baseModule
  return $ moduleRootDir </> moduleBuildDir baseModule </> platformPrefix </> versionDir

getBuildDir :: Module -> App (Path Abs Dir)
getBuildDir baseModule = do
  baseBuildDir <- getBaseBuildDir baseModule
  buildSignature <- B.fromString . T.unpack <$> getBuildSignature baseModule
  buildOptionPrefix <- P.parseRelDir $ "build-option-" ++ B.toString (hashAndEncode buildSignature)
  return $ baseBuildDir </> buildOptionPrefix

writeBuildSignature :: Module -> App ()
writeBuildSignature baseModule = do
  buildDir <- getBuildDir baseModule
  ensureDir buildDir
  let signatureFilePath = buildDir </> signatureFile
  b <- doesFileExist signatureFilePath
  unless b $ do
    buildSignature <- getBuildSignature baseModule
    writeTextFile signatureFilePath buildSignature

getBuildSignature :: Module -> App T.Text
getBuildSignature baseModule = do
  buildMode <- Env.getBuildMode
  optString <- readRef' clangOptString
  let depList = map (second snd) $ Map.toList $ moduleDependency baseModule
  depList' <- fmap catMaybes $ forM depList $ \(alias, digest) -> do
    shiftedDigestOrNone <- Antecedent.lookup digest
    case shiftedDigestOrNone of
      Nothing ->
        return Nothing
      Just shiftedModule ->
        return $ Just (MA.reify alias, E.inject $ _m :< E.String (MID.reify $ moduleID shiftedModule))
  let ens =
        _m
          :< E.Dictionary
            []
            [ ("build-mode", E.inject $ _m :< E.String (BM.reify buildMode)),
              ("extra-clang-option", E.inject $ _m :< E.String (T.pack optString)),
              ("compatible-shift", E.inject $ _m :< E.Dictionary [] depList')
            ]
  return $ E.pp $ E.inject ens

getArtifactDir :: Module -> App (Path Abs Dir)
getArtifactDir baseModule = do
  buildDir <- getBuildDir baseModule
  return $ buildDir </> artifactRelDir

getExecutableDir :: Module -> App (Path Abs Dir)
getExecutableDir baseModule = do
  buildDir <- getBuildDir baseModule
  return $ buildDir </> executableRelDir

sourceToOutputPath :: OK.OutputKind -> Src.Source -> App (Path Abs File)
sourceToOutputPath kind source = do
  artifactDir <- getArtifactDir $ Src.sourceModule source
  relPath <- Src.getRelPathFromSourceDir source
  (relPathWithoutExtension, _) <- P.splitExtension relPath
  Src.attachExtension (artifactDir </> relPathWithoutExtension) kind

getSourceCachePath :: Src.Source -> App (Path Abs File)
getSourceCachePath source = do
  artifactDir <- getArtifactDir $ Src.sourceModule source
  relPath <- Src.getRelPathFromSourceDir source
  (relPathWithoutExtension, _) <- P.splitExtension relPath
  P.addExtension ".i" (artifactDir </> relPathWithoutExtension)

attachOutputPath :: OK.OutputKind -> Src.Source -> App (OK.OutputKind, Path Abs File)
attachOutputPath outputKind source = do
  outputPath <- sourceToOutputPath outputKind source
  return (outputKind, outputPath)

getInstallDir :: FilePath -> App (Path Abs Dir)
getInstallDir filePath = do
  path <- P.resolveDir' filePath
  ensureDir path
  return path
