module Data.Spec where

import Control.Comonad.Cofree (Cofree (..))
import Data.Entity (EntityF (EntityDictionary, EntityString), ppEntityTopLevel)
import qualified Data.HashMap.Lazy as Map
import Data.Module (Alias, Checksum (Checksum))
import qualified Data.Text as T
import Path (Abs, Dir, File, Path, Rel, parent, toFilePath, (</>))

newtype URL
  = URL T.Text
  deriving (Show)

data Spec = Spec
  { specSourceDir :: Path Rel Dir,
    specTargetDir :: Path Rel Dir,
    specEntryPoint :: Map.HashMap T.Text (Path Rel File),
    specDependency :: Map.HashMap Alias (URL, Checksum),
    specLocation :: Path Abs File
  }
  deriving (Show)

addDependency :: Alias -> URL -> Checksum -> Spec -> Spec
addDependency alias url checksum spec =
  spec {specDependency = Map.insert alias (url, checksum) (specDependency spec)}

ppSpec :: Spec -> T.Text
ppSpec spec = do
  let sourceDirText = ppSpecSourceDir spec
  let targetDirText = ppSpecTargetDir spec
  let entryPointText = ppSpecEntryPoint spec
  let dependencyText = ppSpecDependency spec
  T.intercalate "\n\n" [sourceDirText, targetDirText, entryPointText, dependencyText] <> "\n"

ppSpecSourceDir :: Spec -> T.Text
ppSpecSourceDir spec =
  ppEntityTopLevel $ Map.fromList [("source-directory", () :< EntityString (T.pack $ toFilePath $ specSourceDir spec))]

ppSpecTargetDir :: Spec -> T.Text
ppSpecTargetDir spec =
  ppEntityTopLevel $ Map.fromList [("target-directory", () :< EntityString (T.pack $ toFilePath $ specTargetDir spec))]

ppSpecEntryPoint :: Spec -> T.Text
ppSpecEntryPoint spec = do
  let entryPoint = Map.map (\x -> () :< EntityString (T.pack (toFilePath x))) $ specEntryPoint spec
  ppEntityTopLevel $ Map.fromList [("entry-point", () :< EntityDictionary entryPoint)]

ppSpecDependency :: Spec -> T.Text
ppSpecDependency spec = do
  let dependency = flip Map.map (specDependency spec) $ \(URL url, Checksum checksum) -> do
        let urlEntity = () :< EntityString url
        let checksumEntity = () :< EntityString checksum
        () :< EntityDictionary (Map.fromList [("checksum", checksumEntity), ("URL", urlEntity)])
  ppEntityTopLevel $ Map.fromList [("dependency", () :< EntityDictionary dependency)]

wrapWithDict :: T.Text -> Cofree EntityF () -> Cofree EntityF ()
wrapWithDict key value =
  () :< EntityDictionary (Map.fromList [(key, value)])

getSourceDir :: Spec -> Path Abs Dir
getSourceDir spec =
  parent (specLocation spec) </> specSourceDir spec

getTargetDir :: Spec -> Path Abs Dir
getTargetDir spec =
  parent (specLocation spec) </> specTargetDir spec

getEntryPoint :: Spec -> T.Text -> Maybe (Path Abs File)
getEntryPoint spec entryPointName = do
  let sourceDir = getSourceDir spec
  relPath <- Map.lookup entryPointName (specEntryPoint spec)
  return $ sourceDir </> relPath
