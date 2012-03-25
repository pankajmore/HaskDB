\begin{code}
module System.HaskDB.FileHeader where 
import qualified System.HaskDB.FileHandling as FH
import qualified Data.ByteString as BS 
import System.IO 
import Data.Serialize 

-- | Header of The Database to store schema and other related information . Only One thread can operate with the header 
-- at a time . Other threads will be blocked untill allowed . 
--
data Header = Header 
    {fileVersion :: Integer
    }
instance Serialize Header where 
    put h = put $ fileVersion h 
    get = do 
        w <- get 
        return $ Header w 
        
-- | Creates an empty header File .
createHeader :: FH.FHandle -> IO () 
createHeader fh = do 
    fp <- openFile (getHeaderName fh) WriteMode 
    hClose fp 

-- | Change the FileVersion . 
-- TODO : Make read and write together atomic and non failing in case of exception. 
changeFileVersion :: FH.FHandle ->  Integer -> IO () 
changeFileVersion fh bs = do 
    header <- BS.readFile headerPath -- Not necessary initially but when header is not just file version but schema too 
    BS.writeFile headerPath (encode $ Header bs)
  where 
    headerPath = getHeaderName fh 

-- | Get the current Version of the File . 
getFileVersion :: FH.FHandle -> IO Integer
getFileVersion fh = do 
    header <- BS.readFile  $ getHeaderName fh
    case decode header of 
        Left err -> error err 
        Right d -> return $ fileVersion d


-- | Given File Handle return the header file name  
getHeaderName :: FH.FHandle -> FilePath 
getHeaderName fh = FH.filePath fh ++ ".header"
\end{code}    