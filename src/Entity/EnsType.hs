module Entity.EnsType where

import Data.Text qualified as T

data EnsType
  = Int
  | Float
  | Bool
  | String
  | List
  | Dictionary

showEnsType :: EnsType -> T.Text
showEnsType entityType =
  case entityType of
    Int ->
      "int"
    Float ->
      "float"
    Bool ->
      "bool"
    String ->
      "string"
    List ->
      "list"
    Dictionary ->
      "dictionary"
