module Main where


import           System.Environment
import           System.Random


import           Control.Monad
import           Control.Monad.Random
import           Control.Applicative
import qualified Data.Vector as V

import Hopfield
import ConvertImage
import BolzmannMachine

data Method = Hopfield | Boltzmann


transformFunction :: Method -> (Int -> Int)
transformFunction Hopfield  = (\x -> 2 * x - 1)
transformFunction Boltzmann = (\x -> x)

toPattern :: Method -> CBinaryPattern -> Pattern
toPattern m (CBinaryPattern { pattern = pat }) = V.fromList $ map (transformFunction m . fromIntegral) $ pat


recPic :: Method -> (Int, Int) -> [FilePath] -> FilePath -> IO FilePath
recPic method (width, height) imgPaths queryImgPath = do
  l@(queryImg:imgs) <- forM (queryImgPath:imgPaths) (\path -> loadPicture path width height)
  gen <- getStdGen
  let queryPat:imgPats = map (toPattern method) l
      runRand r = evalRand r gen
      i =  case method of
          Hopfield  -> error "This is a trial for Bolzmann"
          Boltzmann -> matchPatternBoltzmann (runRand $ buildBoltzmannData imgPats) queryPat
  return $ imgPaths !! i


main :: IO ()
main = do
  -- TODO use an argument parser (cmdargs)
  methodStr:widthStr:heightStr:queryPath:filePaths <- getArgs
  let method = case methodStr of
                 "hopfield"  -> Hopfield
                 "boltzmann" -> Boltzmann
                 _           -> error "unrecognized method"
      width  = read widthStr
      height = read heightStr
  foundPath <- recPic method (width, height) filePaths queryPath
  putStrLn $ foundPath
