module Entity.Namespace where

import qualified Context.Enum as Enum
import qualified Context.Global as Global
import qualified Context.Locator as Locator
import Context.Throw
import Control.Comonad.Cofree
import Data.Function
import qualified Data.HashMap.Lazy as Map
import Data.IORef
import qualified Data.Text as T
import qualified Data.Text.Internal as Text
import Data.Text.Internal.Search
import Entity.EnumCase
import Entity.Global
import Entity.Hint
import Entity.Ident
import Entity.PrimNum
import qualified Entity.PrimNum.FromText as PrimNum
import qualified Entity.PrimOp.FromText as PrimOp
import Entity.WeakTerm

handleDefinePrefix :: Context -> Hint -> T.Text -> T.Text -> IO ()
handleDefinePrefix context m from to = do
  aliasEnv <- readIORef locatorAliasMapRef
  if Map.member from aliasEnv
    then (context & raiseError) m $ "the prefix `" <> from <> "` is already registered"
    else writeIORef locatorAliasMapRef $ Map.insert from to aliasEnv

{-# INLINE resolveSymbol #-}
resolveSymbol :: Context -> Hint -> (T.Text -> IO (Maybe b)) -> T.Text -> [T.Text] -> IO (Maybe b)
resolveSymbol context m predicate name candList = do
  candList' <- takeAll predicate candList []
  case candList' of
    [] ->
      return Nothing
    [prefixedName] ->
      predicate prefixedName
    _ -> do
      let candInfo = T.concat $ map ("\n- " <>) candList'
      (context & raiseError) m $ "this `" <> name <> "` is ambiguous since it could refer to:" <> candInfo

constructCandList :: Locator.Axis -> T.Text -> Bool -> IO [T.Text]
constructCandList axis name isDefinite = do
  prefixedNameList <- Locator.getPossibleReferents axis name isDefinite
  moduleAliasMap <- readIORef moduleAliasMapRef
  locatorAliasMap <- readIORef locatorAliasMapRef
  return $ map (resolveName moduleAliasMap locatorAliasMap) prefixedNameList

breakOn :: T.Text -> T.Text -> Maybe (T.Text, T.Text)
breakOn pat src@(Text.Text arr off len)
  | T.null pat =
    Nothing
  | otherwise = case indices pat src of
    [] ->
      Nothing
    (x : _) ->
      Just (Text.text arr off x, Text.text arr (off + x) (len - x))

resolveName :: Map.HashMap T.Text T.Text -> Map.HashMap T.Text T.Text -> T.Text -> T.Text
resolveName moduleAliasMap locatorAliasMap name =
  resolveAlias nsSep moduleAliasMap $ resolveAlias definiteSep locatorAliasMap name

resolveAlias :: T.Text -> Map.HashMap T.Text T.Text -> T.Text -> T.Text
resolveAlias sep aliasMap currentName = do
  case breakOn sep currentName of
    Just (currentPrefix, currentSuffix)
      | Just newPrefix <- Map.lookup currentPrefix aliasMap ->
        newPrefix <> currentSuffix
    _ ->
      currentName

takeAll :: (T.Text -> IO (Maybe b)) -> [T.Text] -> [T.Text] -> IO [T.Text]
takeAll predicate candidateList acc =
  case candidateList of
    [] ->
      return acc
    x : xs -> do
      mResult <- predicate x
      case mResult of
        Just _ ->
          takeAll predicate xs (x : acc)
        Nothing ->
          takeAll predicate xs acc

{-# INLINE asWeakVar #-}
asWeakVar :: Hint -> Map.HashMap T.Text Ident -> T.Text -> Maybe WeakTerm
asWeakVar m nenv var =
  Map.lookup var nenv >>= \x -> return (m :< WeakTermVar x)

{-# INLINE asGlobalVar #-}
asGlobalVar :: Global.Axis -> Hint -> T.Text -> IO (Maybe WeakTerm)
asGlobalVar axis m name = do
  b <- Global.isDefined axis name
  if b
    then return $ Just (m :< WeakTermVarGlobal name)
    else return Nothing

{-# INLINE asConstructor #-}
asConstructor :: Global.Axis -> Hint -> T.Text -> IO (Maybe (Hint, T.Text))
asConstructor axis m name = do
  b <- Global.isDefined axis name
  if b
    then return $ Just (m, name)
    else return Nothing

{-# INLINE findThenModify #-}
findThenModify :: Map.HashMap T.Text t -> (T.Text -> a) -> T.Text -> Maybe a
findThenModify env f name = do
  if name `Map.member` env
    then Just $ f name
    else Nothing

{-# INLINE asEnumCase #-}
asEnumCase :: Enum.Axis -> Hint -> T.Text -> IO (Maybe EnumCase)
asEnumCase axis m name = do
  mLabelInfo <- Enum.lookupValue axis name
  return $ mLabelInfo >>= \labelInfo -> return (m :< EnumCaseLabel labelInfo name)

{-# INLINE asEnumIntro #-}
asEnumIntro :: Enum.Axis -> Hint -> T.Text -> IO (Maybe WeakTerm)
asEnumIntro axis m name = do
  mLabelInfo <- Enum.lookupValue axis name
  return $ mLabelInfo >>= \labelInfo -> return (m :< WeakTermEnumIntro labelInfo name)

{-# INLINE asEnum #-}
asEnum :: Enum.Axis -> Hint -> T.Text -> IO (Maybe WeakTerm)
asEnum axis m name = do
  mEnumItems <- Enum.lookupType axis name
  return $ mEnumItems >> return (m :< WeakTermEnum name)

{-# INLINE asWeakConstant #-}
asWeakConstant :: Hint -> T.Text -> Maybe WeakTerm
asWeakConstant m name
  | Just (PrimNumInt _) <- PrimNum.fromText name =
    Just (m :< WeakTermConst name)
  | Just (PrimNumFloat _) <- PrimNum.fromText name =
    Just (m :< WeakTermConst name)
  | Just _ <- PrimOp.fromText name =
    Just (m :< WeakTermConst name)
  | otherwise = do
    Nothing

tryCand :: (Monad m) => m (Maybe a) -> m a -> m a
tryCand comp cont = do
  mx <- comp
  maybe cont return mx