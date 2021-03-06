>  module System.HaskDB.FileHandling where 
>  
>  import System.IO
>  import GHC.Word
>  import qualified Data.ByteString as BS 
>  import qualified Data.ByteString.Char8 as BSC 
>  import Control.Concurrent 
>  import Control.Applicative
>  import System.HaskDB.Fsync 
>  import Data.IORef 
>  -- | New File Handle with blocksize in Bytes stored in the Handle 
>  -- synchVar is used to provide atomicity to read and write operations . 
>  data FHandle = FHandle {
>      fileVersion :: IORef (Integer) ,
>      journalId :: IORef (Integer) , 
>      filePath :: FilePath , 
>      synchVar :: MVar () ,
>      blockSize :: Int ,
>      handle :: Handle
>      }
>  
>  -- | Opens the file given path , mode and BlockSize and returns the file handle 
>  openF :: FilePath -> IOMode -> Int -> IO FHandle 
>  openF fp m bs = do 
>      {-print ("opening handle" ++ fp)-}
>      p <- openBinaryFile fp m
>      sync <- newMVar ()
>      ver <- newIORef 0
>      jid <- newIORef 0
>      return $ FHandle ver jid fp sync bs p
>  
>  
>  -- | Closes the file Handle 
>  closeF :: FHandle -> IO ()
>  closeF fh  = do 
>      {-print ("closing handle" ++ (filePath fh))-}
>      hClose $ handle fh
>  
>  -- | Given the File Handle and block number , reads the block and returns it 
>  readBlock :: FHandle -> Integer -> IO BS.ByteString 
>  readBlock fh i = do 
>      isCl <- hIsClosed (handle fh)
>      if isCl 
>          then 
>          print ("Handle is Closed" ++ (filePath fh))
>          else return ()
>      _ <- takeMVar (synchVar fh)
>      hSeek (handle fh) AbsoluteSeek $ (toInteger $ blockSize fh)*i 
>      ret <- fst <$> BS.foldr (\a (ls,b) -> if (a /= 000) then (BS.cons a ls,True) else ( if b then (BS.cons a ls,b) else (ls,b)) ) (BS.empty,False) <$> BS.hGet (handle fh) (blockSize fh) -- filters out \NUL character . 
>      putMVar (synchVar fh) ()
>      return ret 
>  
>  -- | Given the File Handle and block number and data to be written in ByteString , writes the given block. Adds \NUL if data is less than the block size .  
>  writeBlock :: FHandle -> Integer -> BS.ByteString -> IO () 
>  writeBlock fh i bs = do 
>      _ <- takeMVar (synchVar fh)
>      currentPos <- hTell (handle fh) 
>      hSeek (handle fh) AbsoluteSeek $ (toInteger $ blockSize fh)*i 
>      BS.hPut (handle fh) (BS.take (blockSize fh) (BS.append bs (BS.pack (take (blockSize fh) $ cycle [000 :: GHC.Word.Word8] ))))
>      hSeek (handle fh) AbsoluteSeek currentPos             -- Necessary because concurrent use of appendBlock and writeBlock was resulting in overwriting of block next to where writeBlock was called with append block . 
>      putMVar (synchVar fh) ()
>  
>  -- | Writes all the data . Note that write Block truncates data if size is more than the given block. This will delete all the previous data present in the file. 
>  writeAll :: FHandle -> BS.ByteString -> IO () 
>  writeAll fh bs = do 
>      hSeek (handle fh) AbsoluteSeek 0 
>      BS.hPut (handle fh) bs 
>      size  <- hTell (handle fh) 
>      hSetFileSize (handle fh) size
>  
>  readAll :: FHandle -> IO BS.ByteString
>  readAll fh = do
>      hSeek (handle fh) AbsoluteSeek 0
>      BS.hGetContents (handle fh)
>  
>  -- | Appends a block at the end of the file 
>  appendBlock :: FHandle -> BS.ByteString -> IO Integer
>  appendBlock fh bs = do 
>      hSeek (handle fh) SeekFromEnd 0 
>      currentPos <- hTell (handle fh)
>      BS.hPut (handle fh) (BS.take (blockSize fh) (BS.append bs (BS.pack (take (blockSize fh) $ cycle [000 :: GHC.Word.Word8] ))))
>      return.floor $ (fromIntegral currentPos) / (fromIntegral $ blockSize fh)
>  
>  -- | Reads the last Block of the File and removes if from the File 
>  getLastBlock :: FHandle -> IO (Maybe BS.ByteString)
>  getLastBlock fh = do 
>      fs <- hFileSize (handle fh)
>      if fs > 0 
>          then do 
>              hSeek (handle fh) SeekFromEnd (-(fromIntegral $ blockSize fh))
>              bs <- BS.hGet (handle fh) (blockSize fh)
>              {-bs <- BS.hGet (handle fh) 32-}
>              hSetFileSize (handle fh) (fs - (fromIntegral $ blockSize fh)) 
>              return $ Just bs 
>          else 
>              return Nothing 
>  
>  
>  
>  
>  -- | Flushes the buffer to hard disk 
>  flushBuffer :: FHandle -> IO () 
>  flushBuffer fh = sync $ handle fh 
>  
>  -- | Zeroes out the file . 
>  truncateF :: FHandle -> IO ()
>  truncateF fh = hSetFileSize (handle fh) 0 
>  
>  test = do 
>      c <- openF "abc.b" WriteMode 1024   -- Truncates to zero length file 
>      closeF c
>      p <- openF "abc.b" ReadWriteMode 1024 
>      forkIO $ do 
>          sequence_ $ map (\s -> appendBlock p (BSC.pack (show s))) [1..100]
>      forkIO $ do 
>          sequence_ $ map (\s -> appendBlock p (BSC.pack (show s))) [101..200]
>      appendBlock p (BSC.pack "Hello How are you" )
>      writeBlock p 0 (BSC.pack "First Block")
>      bs <- appendBlock p (BSC.pack "check")
>      print bs
>      threadDelay 1000 -- To keep thread blocked and not close the handle before data is being written . 
>      flushBuffer p 
>      closeF p
>      p <- openF "abc.b" ReadMode 1024
>      x <- sequence $ map (readBlock p) [0..500]
>      print x
>      closeF p


