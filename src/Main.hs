module Main (main) where

import Act.Build qualified as Build
import Act.Check qualified as Check
import Act.Clean qualified as Clean
import Act.Create qualified as Create
import Act.Get qualified as Get
import Act.Release qualified as Release
import Act.Tidy qualified as Tidy
import Act.Version qualified as Version
import Context.App
import Context.OptParse qualified as OptParse
import Context.Throw qualified as Throw
import Entity.Command qualified as C

main :: IO ()
main =
  Main.execute

execute :: IO ()
execute = do
  runApp $ do
    c <- OptParse.parseCommand
    Throw.run $ do
      case c of
        C.Build cfg -> do
          Build.build cfg
        C.Check cfg -> do
          Check.check cfg
        C.Clean cfg ->
          Clean.clean cfg
        C.Release cfg ->
          Release.release cfg
        C.Create cfg ->
          Create.create cfg
        C.Get cfg ->
          Get.get cfg
        C.Tidy cfg ->
          Tidy.tidy cfg
        C.ShowVersion cfg ->
          Version.showVersion cfg
