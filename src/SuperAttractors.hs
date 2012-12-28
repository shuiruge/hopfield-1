{-# LANGUAGE PatternGuards #-}

-- Provides functions to construct and measure networks with super attractors
-- with varying pattern degrees
module SuperAttractors where

import           Control.Monad
import           Control.Monad.Random (MonadRandom)
import qualified Data.Vector as V
import           Hopfield


-- Degree of a pattern is the number of instances it has in a network
type Degree = Int

-- List of Hopfield networks with associated super attractor degree
type Networks = [(Degree, HopfieldData)]


-- A function combining some input and given degree into patterns for a network
type PatternCombiner a = a -> Degree -> [Pattern]


-- List containing each element in xs replicated by the corresponding ns value
-- e.g. mapReplicate [2,3] "ca" = "ccaaa"
mapReplicate :: [Degree] -> [a] -> [a]
mapReplicate ns xs
  = concat $ zipWith replicate ns xs


-- Produces all powers of two <= ceil
powersOfTwo :: Degree -> [Degree]
powersOfTwo ceil = takeWhile (<=ceil) xs
  where
  	xs = 1 : map (*2) xs


-- For each degree in 'ds', builds a network combining the degree and the list
-- of patterns (or some variant) 'as' using the given function 'combine'
buildNetworks :: a -> [Degree] -> PatternCombiner a -> Networks
buildNetworks ps ds combine = map (\d -> (d, buildHopfieldData $ combine ps d)) ds


-- -----------------------------------------------------------------------------
-- Combine functions. 'buildNetworks' uses these to build super attractors

-- Replicates the first pattern k times.
oneSuperAttr :: PatternCombiner [Pattern]
oneSuperAttr ps k = mapReplicate (k:cycle [1]) ps


-- Replicates each pattern k times.
allSuperAttr :: PatternCombiner [Pattern]
allSuperAttr ps k = mapReplicate (cycle [k]) ps


-- Aggregate list of combiner functions of input [Pattern] into a single
-- combiner function of input [[Pattern]]
aggregateCombiners :: [PatternCombiner [Pattern]] -> PatternCombiner [[Pattern]]
aggregateCombiners combiners patList degree
  | length combiners /= length patList
      = error "Number of [Pattern] in list must match number of functions "
  | otherwise
      = concat $ zipWith ($) funcs patList
  where
    funcs = map (($ degree) . flip) combiners

-- Experiments to measure super attractors --

p1, p2 :: Pattern
p1 = V.fromList [1,1,1,-1,-1,1,1,-1,1,-1]
p2 = V.fromList [-1,-1,1,1,-1,-1,1,-1,-1,1]


-- Networks with first pattern as a super attractor
oneSuperNets :: Networks
oneSuperNets = buildNetworks ps degrees oneSuperAttr
  where
    ps      = [p1,p2]
    degrees = powersOfTwo $ V.length $ head ps


-- Networks with all patterns as (equal) super attractors
allSuperNets :: Networks
oneSuperAttractorNets = buildNetworks ps degrees allSuperAttr
  where
    ps      = [p1,p2]
    degrees = powersOfTwo $ V.length $ head ps


-- Measure basin of multiple networks, with various degrees
-- Returns list of tuples: (degree, basinSize)
--
-- Note: degree is not actually used in computation, but rather serves
-- as a label for each network
measureMultiBasins :: MonadRandom m => Networks -> Pattern -> m [(Degree, Int)]
measureMultiBasins nets p = liftM2 zip (return ks) basinSizes
  where
    (ks, hs)   = unzip nets
    basin h    = measurePatternBasin h p
    basinSizes = sequence $ map basin hs
