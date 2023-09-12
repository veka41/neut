module Context.Gensym
  ( newCount,
    readCount,
    writeCount,
    newText,
    newTextFromText,
    newTextForHole,
    newIdentForHole,
    newHole,
    newHoleID,
    newIdentFromText,
    newIdentFromIdent,
    newValueVarLocalWith,
    newTextualIdentFromText,
  )
where

import Context.App
import Context.App.Internal
import Control.Comonad.Cofree
import Control.Monad.Reader
import Data.IORef.Unboxed
import Data.Text qualified as T
import Entity.Comp qualified as C
import Entity.Const
import Entity.Hint
import Entity.HoleID
import Entity.Ident
import Entity.Ident.Reify qualified as Ident
import Entity.RawTerm qualified as RT
import Entity.WeakTerm qualified as WT

newCount :: App Int
newCount =
  asks counter >>= \ref -> liftIO $ atomicAddCounter ref 1

readCount :: App Int
readCount =
  asks counter >>= liftIO . readIORefU

writeCount :: Int -> App ()
writeCount v =
  asks counter >>= \ref -> liftIO $ writeIORefU ref v

{-# INLINE newText #-}
newText :: App T.Text
newText = do
  i <- newCount
  return $ ";" <> T.pack (show i)

{-# INLINE newTextFromText #-}
newTextFromText :: T.Text -> App T.Text
newTextFromText base = do
  i <- newCount
  return $ ";" <> base <> T.pack (show i)

{-# INLINE newTextForHole #-}
newTextForHole :: App T.Text
newTextForHole = do
  i <- newCount
  return $ holeVarPrefix <> ";" <> T.pack (show i)

{-# INLINE newIdentForHole #-}
newIdentForHole :: App Ident
newIdentForHole = do
  text <- newTextForHole
  i <- newCount
  return $ I (text, i)

{-# INLINE newHoleID #-}
newHoleID :: App HoleID
newHoleID = do
  HoleID <$> newCount

{-# INLINE newHole #-}
newHole :: Hint -> [WT.WeakTerm] -> App WT.WeakTerm
newHole m varSeq = do
  i <- HoleID <$> newCount
  return $ m :< WT.Hole i varSeq

{-# INLINE newIdentFromText #-}
newIdentFromText :: T.Text -> App Ident
newIdentFromText s = do
  i <- newCount
  return $ I (s, i)

{-# INLINE newIdentFromIdent #-}
newIdentFromIdent :: Ident -> App Ident
newIdentFromIdent x =
  newIdentFromText (Ident.toText x)

{-# INLINE newValueVarLocalWith #-}
newValueVarLocalWith :: T.Text -> App (Ident, C.Value)
newValueVarLocalWith name = do
  x <- newIdentFromText name
  return (x, C.VarLocal x)

{-# INLINE newTextualIdentFromText #-}
newTextualIdentFromText :: T.Text -> App Ident
newTextualIdentFromText txt = do
  i <- newCount
  newIdentFromText $ ";" <> txt <> T.pack (show i)
