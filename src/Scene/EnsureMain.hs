module Scene.EnsureMain (ensureMain) where

import Context.App
import Context.Locator qualified as Locator
import Context.Throw qualified as Throw
import Control.Monad
import Data.Text qualified as T
import Entity.BaseName qualified as BN
import Entity.DefiniteDescription qualified as DD
import Entity.Hint
import Entity.Source
import Entity.Target

ensureMain :: Target -> Source -> [DD.DefiniteDescription] -> App ()
ensureMain target source topLevelNameList = do
  mainDD <- Locator.getMainDefiniteDescriptionByTarget target
  let hasEntryPoint = mainDD `elem` topLevelNameList
  entryPointIsNecessary <- Locator.checkIfEntryPointIsNecessary target source
  when (entryPointIsNecessary && not hasEntryPoint) $ do
    let entryPointName = getEntryPointName target
    let m = newSourceHint $ sourceFilePath source
    raiseMissingEntryPoint m (BN.reify entryPointName)

type EntryPointName =
  T.Text

raiseMissingEntryPoint :: Hint -> EntryPointName -> App a
raiseMissingEntryPoint m entryPointName = do
  Throw.raiseError m $ "`" <> entryPointName <> "` is missing"