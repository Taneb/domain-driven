module DomainDriven.Internal.Class where

import           Control.Monad.Reader
import           Data.Aeson
import           Data.UUID
import           RIO
import           RIO.Time
import           System.Random
import           GHC.IO.Unsafe                  ( unsafePerformIO )
import qualified RIO.ByteString.Lazy                          as BL
import qualified RIO.ByteString                               as BS
import           Data.Char                      ( ord )
import           System.Directory               ( doesFileExist )

data ESModel model event cmd err m = ESModel
    { persistance :: Persistance event
    , applyEvent :: model -> Stored event -> model
    , cmdHandler :: forall a . (Exception err, MonadIO m, MonadThrow m)
                 => cmd a -> m (model -> Either err (a, [event]))
    , esModel :: TVar model
    } -- deriving Generic

data ESView model event = ESView
    { evantChan :: TChan (Stored event)
    , applyEvent :: model -> Stored event -> model
    , esvModel :: TVar model
    } deriving Generic

-- This should really contain  `TChar [Stored event]` instead.
-- That would allow us to ensure that all or none of the events generated by a single
-- command is stored!
data Persistance event = Persistance
    { eventChan :: TChan [Stored event]
    }

persistEvent :: forall event . Persistance event -> event -> STM (Stored event)
persistEvent (Persistance chan) e = do
    let s = unsafePerformIO $ toStored e
    writeTChan chan s
    pure s

data PersistanceError
    = EncodingError String
    deriving (Show, Eq, Typeable, Exception)

filePersistance :: (Show e, ToJSON e, FromJSON e) => FilePath -> IO (Persistance e)
filePersistance fp = do
    chan <- newTChanIO
    f    <- do
        fileExists <- doesFileExist fp
        if fileExists then readFileBinary fp else pure ""
    let events = fmap eitherDecodeStrict . filter (not . BS.null) $ BS.splitWith
            (== fromIntegral (ord '\n'))
            f
    traverse_ (either (throwM . EncodingError) (atomically . writeTChan chan)) events

    -- Duplicate the channel so that old events are not rewritten
    writerChan <- atomically $ dupTChan chan -- should have type `TChar [Stored event]`
    void . async . forever $ do
        s <- atomically $ readTChan writerChan
        let v = encode s <> BL.singleton (fromIntegral $ ord '\n')
        BL.appendFile fp v
    pure $ Persistance chan

noPersistance :: forall e . IO (Persistance e)
noPersistance = Persistance <$> newTChanIO

runCmd
    :: (Exception err, MonadIO m, MonadThrow m)
    => ESModel model event cmd err m
    -> cmd a
    -> m a
runCmd (ESModel pm appEvent cmdRunner tvar) cmd = do
    cmdTransaction <- cmdRunner cmd
    atomically $ do
        m         <- readTVar tvar
        (r, evs)  <- either throwM pure $ cmdTransaction m
        storedEvs <- traverse (persistEvent pm) evs
        let newModel = foldl' appEvent m storedEvs
        writeTVar tvar newModel
        pure r

class HasModel es model | es -> model where
    getModel :: MonadIO m => es -> m model

instance HasModel (ESModel model e c err m) model where
    getModel = liftIO . readTVarIO . esModel

instance HasModel (ESView model event) model where
    getModel = liftIO . readTVarIO . esvModel

-- | runQuery is reall just readTVar and apply the function...
-- But we will likely want to not export the TVar containing the model, in order to
-- enfore the library is being used correctly.
runQuery :: (HasModel es model, MonadIO m) => es -> (model -> a) -> m a
runQuery es f = f <$> getModel es

data Stored a = Stored
    { storedEvent     :: a
    , storedTimestamp :: UTCTime
    , storedUUID      :: UUID
    } deriving (Show, Eq, Ord, Generic, FromJSON, ToJSON)

mkId :: MonadIO m => (UUID -> b) -> m b
mkId c = c <$> liftIO randomIO

toStored :: MonadIO m => e -> m (Stored e)
toStored e = Stored e <$> getCurrentTime <*> mkId id
