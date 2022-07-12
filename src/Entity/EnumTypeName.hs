module Entity.EnumTypeName
  ( EnumTypeName (..),
  )
where

import Data.Binary
import qualified Entity.DefiniteDescription as DD
import GHC.Generics

newtype EnumTypeName = EnumTypeName {reify :: DD.DefiniteDescription}
  deriving (Show, Generic, Eq, Ord)

instance Binary EnumTypeName