{-# LANGUAGE PatternGuards #-}

-- | Base Hopfield model, providing training and running.
module Hopfield (
    Weights
  , Pattern
  -- * Hopfield data structure
  , HopfieldData ()
  , weights
  , patterns
  , buildHopfieldData
  -- * Running
  , update
  , repeatedUpdate
  , matchPattern
  -- * Energy
  , energy
) where

import           Data.List
import           Data.Maybe
import           Data.Vector (Vector, (!))
import           Data.Vector.Generic.Mutable (write)
import qualified Data.Vector as V

import           Util (repeatUntilEqual)


type Weights = Vector (Vector Int)
type Pattern = Vector Int

-- | Encapsulates the network weights together with the patterns that generate
-- it with the patterns which generate it
data HopfieldData = HopfieldData {
    weights :: Weights    -- ^ the weights of the network
  , patterns :: [Pattern] -- ^ the patterns which were used to train it
}

-- | @buildHopfieldData patterns@: Takes a list of patterns and
-- builds a Hopfield network (by training) in which these patterns are
-- stable states. The result of this function can be used to run a pattern
-- againts the network, by using 'matchPattern'.
buildHopfieldData :: [Pattern] -> HopfieldData
buildHopfieldData []   = error "Train patterns are empty"
buildHopfieldData pats = HopfieldData (train pats) pats


-- | @train patterns@: Trains and constructs network given a list of patterns
-- which are used to build the weight matrix. As a consequence, they will be
-- stable points in the network (by construction).
train :: [Pattern] -> Weights
train pats = vector2D ws
  -- No need to check pats ws size, buildHopfieldData does it
  where
    ws = [ [ w i j | j <- [0 .. neurons-1] ] | i <- [0 .. neurons-1] ]
    w i j
      | i == j    = 0
      | otherwise = sum [ (p ! i) * (p ! j) | p <- pats ]
    neurons     = V.length (head pats)
    vector2D ll = V.fromList (map V.fromList ll)


-- | Same as 'update', without check, for performance.
update' :: Weights -> Pattern -> Pattern
update' ws pat =
  case updatables of
    []  -> pat
    i:_ -> V.modify (\v -> write v i (o i)) pat
  where
    updatables = [ i | (i, x_i) <- zip [1..] (V.toList pat), o i /= x_i ]
    o i        = if sum [ (ws ! i ! j) * (pat ! j)
                        | j <- [0 .. p-1] ] >= 0 then 1 else -1
    p          = V.length pat


-- | @update weights pattern@: Applies the update rule on @pattern@ for the
-- first updatable neuron given the Hopfield network (represented by @weights@).
--
-- Pre: @length weights == length pattern@
update :: Weights -> Pattern -> Pattern
update ws pat
  | Just e <- m_validPattern ws pat = error e
  | otherwise              = update' ws pat


-- | @repeatedUpdate weights pattern@: Performs repeated updates on the given
-- pattern until it reaches a stable state with respect to the Hopfield network
-- (represented by @weights@).
-- Pre: @length weights == length pattern@
repeatedUpdate :: Weights -> Pattern -> Pattern
repeatedUpdate ws pat
  | Just e <- m_validPattern ws pat = error e
  | otherwise              = repeatUntilEqual (update' ws) pat


-- | @matchPatterns hopfieldData pattern@:
-- Computes the stable state of a pattern given a Hopfield network(represented
-- by @weights@) and tries to find a match in a list of patterns which are
-- stored in @hopfieldData@.
-- Returns:
--
--    The index of the matching pattern in @patterns@, if a match exists
--    The converged pattern (the stable state), otherwise
--
-- Pre: @length weights == length pattern@
matchPattern :: HopfieldData -> Pattern -> Either Pattern Int
matchPattern (HopfieldData ws pats) pat
  | Just e <- m_validPattern ws pat = error e
  | otherwise
    = case m_index of
        Nothing    -> Left converged_pattern
        Just index -> Right index
      where
        converged_pattern = repeatedUpdate ws pat
        m_index           = converged_pattern `elemIndex` pats


-- | @energy weights pattern@: Computes the energy of a pattern given a Hopfield
-- network (represented by weights).
-- Pre: @length weights == length pattern@
energy :: Weights -> Pattern -> Int
energy ws pat
  | Just e <- m_validPattern ws pat = error e
  | otherwise = sum [ w i j * x i * x j | i <- [0 .. p-1], j <- [0 .. p-1] ]
    where
      p     = V.length pat
      w i j = ws ! i ! j
      x i   = pat ! i


m_validPattern :: Weights -> Pattern -> Maybe String
m_validPattern ws pat
  | V.length ws /= V.length pat = Just "Pattern size must match network size"
  | otherwise                   = Nothing


-- TODO get first like with the patterns, instead of using random
m_validPatterns :: Weights -> [Pattern] -> Maybe String
m_validPatterns ws pats =
    Just $ concat . intersperse ", " . map show $ invalid_pattern_indices
    where
      valid_patterns = map (isNothing . m_validPattern ws) pats
      bool_index_pairs = zip [0..] valid_patterns
      invalid_pattern_indices = [ i | (i, valid) <- bool_index_pairs, valid ]

-- | @validWeights weights@: Validates the weight matrix's correctness:
-- * It is non-empty
-- * It is square
-- * It is symmetric
-- * All diagonal elements must be zero
-- Throws an error if the weight matrix is invalid.
--validWeights :: Weights -> Bool
--validWeights ws
--  | n == 0
--    = error "Weight matrix must be non-empty"
--  | not $ allEquals $ [n] ++ (map V.length $ V.toList ws)
--    = error "Weight matrix must be square"
--  | not $ all (== 0) [ ws ! i ! i | i <- [0..n-1]]
--    = error "Weight matrix diagonal must be zero"
--  | not $ and [ (ws ! i ! j) == (ws ! j ! i) | i <- [0..n-1], j <- [0..n-1]]
--    = error "Weight matrix must be symmetric"
--  | otherwise = True
--  where
--    n = V.length ws

