{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
module GUI.StartupInfoView (
    StartupInfoView,
    startupInfoViewNew,
    startupInfoViewSetEvents,
  ) where

import GHC.RTS.Events

import Graphics.UI.Gtk
import qualified Graphics.UI.Gtk.ModelView.TreeView.Compat as Compat

import Data.Array
import Data.List
import Data.Maybe
import Data.Time
import Data.Time.Clock.POSIX
import Data.Text (Text)
import qualified Data.Text as T

-------------------------------------------------------------------------------

data StartupInfoView = StartupInfoView
     { labelProgName      :: Label
     , storeProgArgs      :: ListStore Text
     , storeProgEnv       :: ListStore (Text, Text)
     , labelProgStartTime :: Label
     , labelProgRtsId     :: Label
     }

data StartupInfoState
   = StartupInfoEmpty
   | StartupInfoLoaded
     { progName      :: Maybe Text
     , progArgs      :: Maybe [Text]
     , progEnv       :: Maybe [(Text, Text)]
     , progStartTime :: Maybe UTCTime
     , progRtsId     :: Maybe Text
     }

-------------------------------------------------------------------------------

startupInfoViewNew :: Builder -> IO StartupInfoView
startupInfoViewNew builder = do

    let getWidget cast = builderGetObject builder cast

    labelProgName      <- getWidget castToLabel    ("labelProgName" :: Text)
    treeviewProgArgs   <- getWidget castToTreeView ("treeviewProgArguments" :: Text)
    treeviewProgEnv    <- getWidget castToTreeView ("treeviewProgEnvironment" :: Text)
    labelProgStartTime <- getWidget castToLabel    ("labelProgStartTime" :: Text)
    labelProgRtsId     <- getWidget castToLabel    ("labelProgRtsIdentifier" :: Text)

    storeProgArgs    <- listStoreNew []
    columnArgs       <- treeViewColumnNew
    cellArgs         <- cellRendererTextNew

    treeViewColumnPackStart columnArgs cellArgs True
    treeViewAppendColumn treeviewProgArgs columnArgs

    Compat.treeViewSetModel treeviewProgArgs (Just storeProgArgs)

    set cellArgs [ cellTextEditable := True ]
    cellLayoutSetAttributes columnArgs cellArgs storeProgArgs $ \arg ->
      [ cellText := arg ]

    storeProgEnv     <- listStoreNew []
    columnVar        <- treeViewColumnNew
    cellVar          <- cellRendererTextNew
    columnValue      <- treeViewColumnNew
    cellValue        <- cellRendererTextNew

    treeViewColumnPackStart columnVar   cellVar   False
    treeViewColumnPackStart columnValue cellValue True
    treeViewAppendColumn treeviewProgEnv columnVar
    treeViewAppendColumn treeviewProgEnv columnValue

    Compat.treeViewSetModel treeviewProgEnv (Just storeProgEnv)

    cellLayoutSetAttributes columnVar cellVar storeProgEnv $ \(var,_) ->
      [ cellText := var ]

    set cellValue [ cellTextEditable := True ]
    cellLayoutSetAttributes columnValue cellValue storeProgEnv $ \(_,value) ->
      [ cellText := value ]

    let startupInfoView = StartupInfoView{..}

    return startupInfoView

-------------------------------------------------------------------------------

startupInfoViewSetEvents :: StartupInfoView -> Maybe (Array Int Event) -> IO ()
startupInfoViewSetEvents view mevents =
    updateStartupInfo view (maybe StartupInfoEmpty processEvents mevents)

--TODO: none of this handles the possibility of an eventlog containing multiple
-- OS processes. Note that the capset arg is ignored in the events below.

processEvents :: Array Int Event -> StartupInfoState
processEvents = foldl' accum (StartupInfoLoaded Nothing Nothing Nothing Nothing Nothing)
              . take 1000
              . elems
  where
    accum info (Event _ (ProgramArgs _ (name:args)) _) =
      info {
        progName = Just name,
        progArgs = Just args
      }

    accum info (Event _ (ProgramEnv _ env) _) =
      info { progEnv = Just (sort (parseEnv env)) }

    accum info (Event _ (RtsIdentifier _ rtsid) _) =
      info { progRtsId = Just rtsid }

    accum info (Event timestamp (WallClockTime _ sec nsec) _) =
          -- WallClockTime records the wall clock time of *this* event
          -- which occurs some time after startup, so we can just subtract
          -- the timestamp since that is the relative time since startup.
      let wallTimePosix :: NominalDiffTime
          wallTimePosix = fromIntegral sec
                        + (fromIntegral nsec / nanoseconds)
                        - (fromIntegral timestamp / nanoseconds)
          nanoseconds   = 1000000000
          wallTimeUTC   = posixSecondsToUTCTime wallTimePosix
      in  info { progStartTime = Just wallTimeUTC }

    accum info _ = info

    -- convert ["foo=bar", ...] to [("foo", "bar"), ...]
    parseEnv env = [ (var, value) | (var, T.drop 1 -> value) <- map (T.span (/='=')) env ]

updateStartupInfo :: StartupInfoView -> StartupInfoState -> IO ()
updateStartupInfo StartupInfoView{..} StartupInfoLoaded{..} = do
    set labelProgName      [ labelText := fromMaybe "(unknown)"  progName ]
    set labelProgStartTime [ labelText := maybe "(unknown)" show progStartTime ]
    set labelProgRtsId     [ labelText := fromMaybe "(unknown)"  progRtsId ]
    listStoreClear storeProgArgs
    mapM_ (listStoreAppend storeProgArgs) (fromMaybe [] progArgs)
    listStoreClear storeProgEnv
    mapM_ (listStoreAppend storeProgEnv) (fromMaybe [] progEnv)

updateStartupInfo StartupInfoView{..} StartupInfoEmpty = do
    set labelProgName      [ labelText := ("" :: Text) ]
    set labelProgStartTime [ labelText := ("" :: Text) ]
    set labelProgRtsId     [ labelText := ("" :: Text) ]
    listStoreClear storeProgArgs
    listStoreClear storeProgEnv
