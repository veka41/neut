module Entity.Cache where

import Data.Binary
import Entity.LocationTree qualified as LT
import Entity.NameArrow qualified as NA
import Entity.Remark
import Entity.Stmt
import GHC.Generics

data Cache = Cache
  { stmtList :: [Stmt],
    remarkList :: [Remark],
    nameArrowList :: [NA.NameArrow],
    locationTree :: LT.LocationTree
  }
  deriving (Generic)

instance Binary Cache
