module Entity.RawIdent
  ( RawIdent,
    isHole,
  )
where

import Data.Text qualified as T
import Entity.Const (holeVarPrefix)

type RawIdent =
  T.Text

isHole :: RawIdent -> Bool
isHole var =
  holeVarPrefix `T.isPrefixOf` var
