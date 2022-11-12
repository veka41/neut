module Entity.GlobalName (GlobalName (..)) where

import Entity.Arity
import qualified Entity.DefiniteDescription as DD
import Entity.Discriminant
import Entity.EnumInfo
import qualified Entity.EnumTypeName as ET
import qualified Entity.PrimNumType as PNT
import Entity.PrimOp

data GlobalName
  = TopLevelFunc Arity
  | EnumType [EnumValue]
  | EnumIntro ET.EnumTypeName Discriminant
  | PrimType PNT.PrimNumType
  | PrimOp PrimOp
  | Data Arity [DD.DefiniteDescription]
  deriving (Show)
