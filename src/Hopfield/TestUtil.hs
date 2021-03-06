{-# LANGUAGE ParallelListComp #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Hopfield.TestUtil where

-- Util functions used for test
-- Mostly properties and generators

import           Control.Applicative
import           Control.Monad
import           Control.Monad.Random
import           Data.Vector ((!))
import qualified Data.Vector as V
import           Test.QuickCheck

import           Hopfield.Hopfield
import           Hopfield.Measurement
import           Hopfield.Boltzmann.RestrictedBoltzmannMachine
import           Hopfield.Util


data Type = H | BM

-- Warning: orphan instance. For more details see:
-- http://stackoverflow.com/questions/3079537/orphaned-instances-in-haskell
-- The way to avoid it is to make a warpper around Vector.
instance (Arbitrary a) => Arbitrary (V.Vector a) where
  arbitrary = fmap V.fromList arbitrary

nonempty :: forall a. Gen [a] -> Gen [a]
nonempty = (`suchThat` (not . null))

mapMonad :: Monad m => (a -> b) -> m [a] -> m [b]
mapMonad f m_xs = do
  xs <- m_xs
  return $ map f xs


-- | Convert a list generator to a vector generator
toGenVector :: Gen [a] -> Gen (V.Vector a)
toGenVector listGen = fmap V.fromList listGen


-- | Generate a random sign (+/- 1)
signGen :: Gen Int
signGen = do
  n <- choose (0,1)
  return $ n*2 - 1

binaryGen :: Gen Int
binaryGen = do
  n <- choose (0,1)
  return n

-- | @patternGen n@: Generates patterns of size n
patternGen :: Type -> Int -> Gen Pattern
patternGen H  n = toGenVector $ vectorOf n signGen
patternGen BM n = toGenVector $ vectorOf n binaryGen


-- | @patternRangeGen (min, max)@ Generates patterns of size ranging
-- between min and max
patternRangeGen :: Type -> (Int, Int) -> Gen Pattern
patternRangeGen t bounds = choose bounds >>= patternGen t


-- | @boundedListGen g n@: Generates lists (max length n) of the given Gen
boundedListGen :: Gen a -> Int -> Gen [a]
boundedListGen g n = do
  len <- choose (0, n)
  vectorOf len g

-- | @patListGen t maxPatSize maxPatListSize@ Generates a list of patterns.
-- The size of each pattern is less than maxPatSize.
-- The size odf the list is less than maxPatListSize.
-- The type is required in order to create types specific for Boltzmann, 
-- Hopfield etc.
patListGen :: Type -> Int -> Int -> Gen [Pattern]
patListGen t maxPatSize maxPatListSize = do
    i <- choose (1, maxPatSize)
    nonempty $ boundedListGen (patternGen t i) maxPatListSize


-- | @patternsTupleGen g m1 m2@Generates a tuple of lists, as follows:
-- Uses patListGen to generate 1 list of patterns with length less than m2.
-- The list itself has to have length less than m1.
-- The second element of a tuple is a list of patterns which have the same size
-- as the patterns of the first list.
patternsTupleGen :: Type -> Int -> Int -> Gen ([Pattern], [Pattern])
patternsTupleGen t m1 m2 = do
  fst_list <- patListGen t m1 m2
  i <- choose (0, m2)
  snd_list <- vectorOf i (patternGen t $ V.length $ head fst_list)
  return $ (fst_list, snd_list)


-- Generate lists containing only 'x'
sameElemList :: a -> Gen [a]
sameElemList x = do
  len <- arbitrary
  return $ replicate len x


-- | Generate vectors containing the same element replicated
sameElemVector :: a -> Gen (V.Vector a)
sameElemVector = toGenVector . sameElemList


-- | Produces a matrix with 0's along the diagonal and 1's otherwise
allWeightsSame :: Int -> [[Double]]
allWeightsSame n
  = [ [ if i==j then 0 else w | i <- [0..n-1] ] | j <- [0..n-1] ]
    where w = (1 :: Int) ./. n


-- | @boundedReplicateGen n g@ Generates lists containing 'g' replicated.
-- The list is bounded in size by n.
boundedReplicateGen :: Int -> Gen a -> Gen [a]
boundedReplicateGen n g = liftM2 replicate (choose (0, n)) g


-- | Replaces the nth element in the list with 'r'
replaceAtN :: Int -> a -> [a] -> [a]
replaceAtN _ _ []     = error "index greater than list size"
replaceAtN 0 r (_:xs) = (r:xs)
replaceAtN n r (x:xs)
  | n > 0     = (x:(replaceAtN (n-1) r xs))
  | otherwise = error "negative index"


-- | Compute crosstalk term for a pattern and a given neuron
-- @crosstalk hopfield index neuron
-- todo think if it is better to actually pass in the hopfield data
-- strucutre
-- the pattern on which we do this has to be one of the traninig patterns
-- todo error checks
-- note that this is a very basic check
-- one should try and implement the probability error thing as
-- that would give as a good idea of how to
-- scale
crosstalk :: HopfieldData -> Int -> Int -> Int
-- the cross talk term is h(xi k ) - xi k
crosstalk hs index n = computeH (weights hs) pat n - pat ! n
                          where pat = (patterns hs) !! index


-- | Used as a property to check that patterns which
-- are used to create the network are stable in respect to update
trainingPatsAreFixedPoints :: LearningType -> [Pattern] -> Gen Bool
trainingPatsAreFixedPoints method pats =
  and <$> mapM checkFixedPoint [0.. length pats - 1]
  where
    hs = buildHopfieldData method pats
    ws = weights hs
    checkFixedPoint index = do
      i <- arbitrary
      return $ evalRand (update ws (pats !! index)) (mkStdGen i) == Nothing || (not $ checkFixed hs index)


-- | Trains a network using @training_pats@ and then updates each
-- pattern in pats according to the weights of that network.
-- The aim is to check that the energy decreases after each update.
energyDecreasesAfterUpdate :: LearningType -> ([Pattern], [Pattern]) -> Gen Bool
energyDecreasesAfterUpdate method (training_pats, pats)
  = and <$> (forM pats $ \pat -> do
              i <- arbitrary
              return $ evalRand (energyDecreases pat) (mkStdGen i)
            )
    where
      ws = weights $ buildHopfieldData method training_pats
      check pat afterPat = energy ws pat >= energy ws afterPat || energy ws afterPat - energy ws pat <= 0.00000001
      energyDecreases :: (MonadRandom m) => Pattern -> m Bool
      energyDecreases pat = do
        maybe_pat  <- update ws pat
        case maybe_pat of
          Nothing -> return True
          Just updatedPattern -> return $ check pat updatedPattern


-- TODO mihaela unused?
repeatedUpdateCheck :: LearningType -> ([Pattern], [Pattern]) -> Gen Bool
repeatedUpdateCheck method (training_pats, pats)
  = and <$> mapM  s pats
    where
      ws = weights $ buildHopfieldData method training_pats
      stopped pat = do
        p     <- converged_pattern
        maybe_new_p <- update ws p
        return $ maybe_new_p == Nothing
        where
          converged_pattern = repeatedUpdate ws pat
      s pat = do
        i <- arbitrary
        return $ evalRand (stopped pat) (mkStdGen i)

-- | @boltzmannBuildGen maxPatSize maxPatListSize max_hidden@ 
-- Generates the structures required for creating a Boltzmann machine: 
-- a list of patterns together with the number of hidden layers,
-- which has to be less than max_hidden.
boltzmannBuildGen :: Int -> Int -> Int -> Gen ([Pattern], Int)
boltzmannBuildGen maxPatSize maxPatListSize max_hidden = do
  pats <- patListGen BM maxPatSize maxPatListSize
  i    <- choose (1, max_hidden)
  return $ (pats, i)

--  | Checks that the buildBoltzmann function does not modify
-- the given patterns or the number of hidden layers.
buildBoltzmannCheck :: ([Pattern], Int) -> Gen Bool
buildBoltzmannCheck (pats, nr_h) = do
  i <- arbitrary
  let bd = evalRand (buildBoltzmannData' pats nr_h) (mkStdGen i)
  return $ patternsB bd == pats && nr_hiddenB bd == nr_h

-- | Generates a list of patterns and the number of hidden layers
-- used to train a Boltzmann machine, as well as a generic pattern to 
-- recognize on this machine.
boltzmannAndPatGen :: Int -> Int -> Int -> Gen ([Pattern], Int, Pattern)
boltzmannAndPatGen maxPatSize maxPatListSize max_hidden = do
  pats_train <- patListGen BM maxPatSize maxPatListSize
  i          <- choose (1, max_hidden)
  pats_check <- patternGen BM (V.length $ pats_train !! 0)
  return $ (pats_train, i, pats_check)

-- | @probabilityCheck (pats, nr_h, pat)@. Trains a Boltzmann machine
-- using @pats@ and @nr_h@ and computes the activation probability for 
-- @pat@ using this machine, and check if it is indeed a probability,
-- ie in [0,1]
probabilityCheck ::  ([Pattern], Int, Pattern) -> Gen Bool
probabilityCheck (pats, nr_h, pat) = do
  seed <- arbitrary
  let bd = evalRand (buildBoltzmannData' pats nr_h) (mkStdGen seed)
      ws = weightsB bd
  return $ all  (\x -> c $ getActivationProbability Matching Visible ws pat x) [0 .. nr_h - 1]
    where c x = x <= 1 && x >=0


-- -- r should only be 0 or 1 for this test
updateNeuronCheck :: Int -> ([Pattern], Int, Pattern) -> Gen Bool
updateNeuronCheck r (pats, nr_h, pat)
    | not (r == 0 || r == 1) = error "r has to be 0 or 1 for updateNeuronCheck"
    | otherwise = do
        i    <- choose (0, nr_h -1)
        seed <- arbitrary
        let bd = evalRand (buildBoltzmannData' pats nr_h) (mkStdGen seed)
        return $ updateNeuron' (fromIntegral r) Matching Visible (weightsB bd) pat i == (1 - r)


-- TODO write comment and change the name to show the restrictions
buildIntTuple :: Gen (Int, Int)
buildIntTuple = do
  i <- choose (1, 100)
  let min_size = ceiling $ log2 $ fromIntegral i
  j <- choose (min_size + 1, min_size + 2)
  return (i, j)


binaryCheck :: (Int, Int) -> Bool
binaryCheck (x, y) = x == refold
 where
   refold = sum [ b * 2^pos | b <- reverse bits | pos <- [(0:: Int)..] ]
   bits   = toBinary x y


-- Runs expressions requiring random numbers (e.g. RandomMonad) in the Gen monad
evalRandGen :: Rand StdGen a -> Gen a
evalRandGen e = do
  rndInt <- arbitrary
  return $ evalRand e (mkStdGen rndInt)
