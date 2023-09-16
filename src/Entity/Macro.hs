module Entity.Macro
  ( Arg (..),
    Args,
    Rules,
    Sub,
    MacroInfo,
    showArg,
    showArgs,
  )
where

import Data.Binary
import Data.HashMap.Strict qualified as Map
import Data.Text qualified as T
import Entity.RawIdent
import Entity.Tree
import GHC.Generics (Generic)

data Arg
  = Literal RawIdent
  | Var RawIdent
  | Str T.Text
  | ArgNode Args
  | ArgList Args
  deriving (Show, Generic)

instance Binary Arg

type Args =
  ([Arg], Maybe RawIdent)

type Rules =
  Map.HashMap RawIdent [(Args, Tree)]

type Sub =
  Map.HashMap RawIdent Tree

type MacroInfo =
  (RawIdent, [(Args, Tree)])

showArg :: Arg -> T.Text
showArg arg =
  case arg of
    Literal sym ->
      "'" <> sym
    Var var ->
      var
    Str str ->
      "\"" <> str <> "\""
    ArgNode args ->
      "(" <> showArgs args <> ")"
    ArgList args ->
      "[" <> showArgs args <> "]"

showArgs :: Args -> T.Text
showArgs (argList, mRest) =
  case mRest of
    Nothing ->
      T.intercalate " " (map showArg argList)
    Just rest ->
      T.intercalate " " (map showArg argList) <> " " <> rest
