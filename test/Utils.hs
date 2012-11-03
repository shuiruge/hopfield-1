module Utils where

import Control.Applicative
import Control.Monad
import Control.Monad.Random
import qualified Data.Vector as V
import Test.QuickCheck
import Control.Monad

import Hopfield


-- | Defines an arbitrary vector
instance (Arbitrary a) => Arbitrary (V.Vector a) where
  arbitrary = liftM V.fromList arbitrary


mapMonad :: Monad m => (a -> b) -> m [a] -> m [b]
mapMonad f m_xs = do
  xs <- m_xs
  return $ map f xs


-- | Convert a list generator to a vector generator
toGenVector :: Gen [a] -> Gen (V.Vector a)
toGenVector listGen = liftM V.fromList listGen


randomSign :: Int -> Int
randomSign x
  | even x = 1
  | otherwise = -1


-- | Generate lists containing the same element replicated
patternGen :: Int -> Gen Pattern
patternGen len = toGenVector $ mapMonad randomSign (vectorOf len arbitrary)


patternListGen :: Gen [Pattern]
patternListGen = do
  vector_len  <- arbitrary
  listOf1 $ patternGen $ (abs vector_len + 1) `mod` 100 + 1


-- Generate lists containing only 'x'
sameElemList :: a -> Gen [a]
sameElemList x = do
  len <- arbitrary
  return $ replicate len x


-- | Generate vectors containing the same element replicated
sameElemVector :: a -> Gen (V.Vector a)
sameElemVector = toGenVector . sameElemList


-- | Produces a matrix with 0's along the diagonal and 1's otherwise
allOnesWeights :: Int -> V.Vector (V.Vector Double)
allOnesWeights n
  = V.fromList $ map V.fromList [ replaceAtN i 0 ones | i <- [0..n-1] ]
    where
      ones = replicate n 1


replicateGen :: Gen a -> Gen [a]
replicateGen g = liftM2 replicate arbitrary g


-- | Replaces the nth element in the list with 'r'
replaceAtN :: Int -> a -> [a] -> [a]
replaceAtN _ _ []     = error "index greater than list size"
replaceAtN 0 r (x:xs) = (r:xs)
replaceAtN n r (x:xs)
  | n > 0     = (x:(replaceAtN (n-1) r xs))
  | otherwise = error "negative index"


--converts a list of lists to a vector or vectors
matrixToVectors :: [[a]] -> V.Vector ( V.Vector a)
matrixToVectors matrix = V.fromList (map V.fromList matrix)

-- | Used as a property to check that patterns which
-- are used to create the network are stable in respect to update
trainingPatsAreFixedPoints:: [Pattern] -> Gen Bool
trainingPatsAreFixedPoints pats =
  and <$> mapM checkFixedPoint pats
  where
    ws = weights (buildHopfieldData pats)
    checkFixedPoint pat = do
      i <- arbitrary
      return $ evalRand (update ws pat) (mkStdGen i) == pat
