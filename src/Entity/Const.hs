{-# LANGUAGE TemplateHaskell #-}

module Entity.Const where

import Data.Text qualified as T
import Path

sourceFileExtension :: String
sourceFileExtension =
  ".nt"

packageFileExtension :: T.Text
packageFileExtension =
  ".tar.zst"

nsSepChar :: Char
nsSepChar =
  '.'

nsSep :: T.Text
nsSep =
  T.singleton nsSepChar

verSep :: T.Text
verSep =
  "-"

envVarCacheDir :: String
envVarCacheDir =
  "NEUT_CACHE_DIR"

envVarCoreModuleURL :: String
envVarCoreModuleURL =
  "NEUT_CORE_MODULE_URL"

envVarCoreModuleDigest :: String
envVarCoreModuleDigest =
  "NEUT_CORE_MODULE_DIGEST"

envVarClang :: String
envVarClang =
  "NEUT_CLANG"

macroMaxStep :: Int
macroMaxStep =
  2000

moduleFile :: Path Rel File
moduleFile =
  $(mkRelFile "module.ens")

sourceRelDir :: Path Rel Dir
sourceRelDir =
  $(mkRelDir "source")

buildRelDir :: Path Rel Dir
buildRelDir =
  $(mkRelDir "build")

archiveRelDir :: Path Rel Dir
archiveRelDir =
  $(mkRelDir "archive")

artifactRelDir :: Path Rel Dir
artifactRelDir =
  $(mkRelDir "artifact")

executableRelDir :: Path Rel Dir
executableRelDir =
  $(mkRelDir "executable")

attrPrefix :: T.Text
attrPrefix =
  ":"

core :: T.Text
core =
  "core"

coreUnit :: T.Text
coreUnit =
  core <> nsSep <> "unit" <> nsSep <> "unit"

coreUnitUnit :: T.Text
coreUnitUnit =
  core <> nsSep <> "unit" <> nsSep <> "Unit"

coreBool :: T.Text
coreBool =
  core <> nsSep <> "bool" <> nsSep <> "bool"

coreBoolTrue :: T.Text
coreBoolTrue =
  core <> nsSep <> "bool" <> nsSep <> "True"

coreBoolFalse :: T.Text
coreBoolFalse =
  core <> nsSep <> "bool" <> nsSep <> "False"

coreExcept :: T.Text
coreExcept =
  core <> nsSep <> "except" <> nsSep <> "except"

coreExceptFail :: T.Text
coreExceptFail =
  core <> nsSep <> "except" <> nsSep <> "Fail"

coreExceptPass :: T.Text
coreExceptPass =
  core <> nsSep <> "except" <> nsSep <> "Pass"

coreExceptOption :: T.Text
coreExceptOption =
  core <> nsSep <> "except" <> nsSep <> "option"

coreExceptNoneInternal :: T.Text
coreExceptNoneInternal =
  core <> nsSep <> "except" <> nsSep <> "none-internal"

coreExceptSomeInternal :: T.Text
coreExceptSomeInternal =
  core <> nsSep <> "except" <> nsSep <> "some-internal"

corePair :: T.Text
corePair =
  core <> nsSep <> "pair" <> nsSep <> "pair"

corePairPair :: T.Text
corePairPair =
  core <> nsSep <> "pair" <> nsSep <> "Pair"

coreList :: T.Text
coreList =
  core <> nsSep <> "list" <> nsSep <> "list"

coreListNil :: T.Text
coreListNil =
  core <> nsSep <> "list" <> nsSep <> "Nil"

coreListCons :: T.Text
coreListCons =
  core <> nsSep <> "list" <> nsSep <> "Cons"

coreText :: T.Text
coreText =
  core <> nsSep <> "text" <> nsSep <> "text"

coreSystemAdmit :: T.Text
coreSystemAdmit =
  core <> nsSep <> "system" <> nsSep <> "admit"

coreSystemAssert :: T.Text
coreSystemAssert =
  core <> nsSep <> "system" <> nsSep <> "assert"

coreThreadFlowInner :: T.Text
coreThreadFlowInner =
  core <> nsSep <> "thread" <> nsSep <> "flow-inner"

coreThreadDetach :: T.Text
coreThreadDetach =
  core <> nsSep <> "thread" <> nsSep <> "detach"

coreThreadAttach :: T.Text
coreThreadAttach =
  core <> nsSep <> "thread" <> nsSep <> "attach"

holeVarPrefix :: T.Text
holeVarPrefix =
  "{}"

unsafeArgcName :: T.Text
unsafeArgcName =
  "neut-unsafe-argc"

unsafeArgvName :: T.Text
unsafeArgvName =
  "neut-unsafe-argv"
