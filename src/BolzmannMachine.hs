{-# LANGUAGE PatternGuards, ScopedTypeVariables #-}

module BolzmannMachine where
-- | Base Restricted Bolzamann machine.

-- http://en.wikipedia.org/wiki/Restricted_Boltzmann_machine

-- Using RBM for recognition
-- http://uai.sis.pitt.edu/papers/11/p463-louradour.pdf
-- http://www.dmi.usherb.ca/~larocheh/publications/drbm-mitacs-poster.pdf

import           Data.Maybe
import           Data.Tuple
import           Control.Applicative
import           Control.Monad
import           Control.Monad.Random
import           Data.List
import           Data.Vector ((!))
import qualified Data.Vector as V
import qualified Numeric.Container as NC

import Common
import Util

-- In the case of the Bolzamann Machine the weight matrix establishes the
-- weigths between visible and hidden neurons
-- w i j - connection between visible neuron i and hidden neuron j

-- | determines the rate in which the weights are changed in the training phase.
-- http://en.wikipedia.org/wiki/Restricted_Boltzmann_machine#Training_algorithm
learningRate = 0.1 :: Double


data Mode = Hidden | Visible
  deriving(Eq, Show)


 -- data Phase = Training | Matching
--  deriving(Eq, Show)


data BoltzmannData = BoltzmannData {
    weightsB :: Weights    -- ^ the weights of the network
  , classificationWeights :: Weights -- weigths for classification
  ,  b  :: Bias
  ,  c  :: Bias
  ,  d  :: Bias
  , patternsB :: [Pattern] -- ^ the patterns which were used to train it
  -- can be decuded from weights, maybe should be remove now
  , nr_hidden :: Int       -- ^ number of neurons in the hidden layer
  , pattern_to_class :: [(Pattern, Int)] -- the class of the given pattern
    -- classes have to be in consecutive order, from 0
}
  deriving(Show)


-- | Retrieves the dimension of the weights matrix corresponding to the given mode.
-- For hidden, it is the width of the matrix, and for visible it is the height.
getDimension :: Mode -> Weights -> Int
getDimension Hidden ws  = V.length $ ws ! 0
getDimension Visible ws = V.length $ ws


buildBoltzmannData ::  MonadRandom  m => [Pattern] ->  m BoltzmannData
buildBoltzmannData []   = error "Train patterns are empty"
buildBoltzmannData pats =
  --nr_hidden <- getRandomR (floor (1.0/ 10.0 * nr_visible), floor (1.0/ 9.0 * nr_visible))
  -- TODO replace with getRandomR with bigger range
  buildBoltzmannData' pats (floor (logBase 2 nr_visible) - 3)
    where nr_visible = fromIntegral $ V.length (head pats)


-- | @buildBolzmannData' patterns nr_hidden@: Takes a list of patterns and
-- builds a Bolzmann network (by training) in which these patterns are
-- stable states. The result of this function can be used to run a pattern
-- against the network, by using 'matchPatternBolzmann'.
buildBoltzmannData' :: MonadRandom  m => [Pattern] -> Int ->  m BoltzmannData
buildBoltzmannData' [] _  = error "Train patterns are empty"
buildBoltzmannData' pats nr_hidden
  | first_len == 0
      = error "Cannot have empty patterns"
  | any (\x -> V.length x /= first_len) pats
      = error "All training patterns must have the same length"
  | otherwise = trainBolzmann pats nr_hidden
  where
    first_len = V.length (head pats)

-- TODO add error check that we have a in 0.0 to 1
gibbsSampling :: MonadRandom  m => Double -> m Int
gibbsSampling a = do
  r <- getRandomR (0.0, 0.1)
  return $ if (r < a) then 1 else 0

-- @getActivationProbability ws bias pat index@
-- can be used to compute the activation probability for a neuron in the
-- visible layer, or for parts of the sums requires for
-- the probabilty of the classifications
getActivationSum :: Weights -> Bias -> Pattern -> Int -> Double
getActivationSum ws bias pat index
-- TODO replace with dot product function by using column function for ws
  = bias ! index + sum [(ws ! i ! index) *. (pat ! i) | i <- [0 .. p-1] ]
    where
      p = V.length pat


getActivationProbabilityVisible :: Weights -> Bias -> Pattern -> Int -> Double
getActivationProbabilityVisible ws bias h index
  = activation $ getActivationSum ws bias h index

-- assertion same size and move to Util
dotProduct :: Num a => V.Vector a -> V.Vector a -> a
dotProduct xs ys
  = sum [ xs ! i * (ys ! i ) | i <- [0.. V.length xs - 1]]

getActivationSumHidden :: Weights -> Weights ->  Bias -> Pattern -> Pattern -> Int -> Double
getActivationSumHidden ws u c v y index
  = c ! index + dotProduct (ws ! index) (to_double v) + dotProduct (u ! index) (to_double y)
      where to_double = fmap fromIntegral


getHiddenSums :: Weights -> Weights ->  Bias -> Pattern -> Pattern -> V.Vector Double
getHiddenSums ws u c v y
  = V.fromList [getActivationSumHidden ws u c v y i | i <- [0 .. (V.length $ ws ! 0) - 1] ]


getActivationProbabilityHidden ::  Weights -> Weights ->  Bias -> Pattern -> Pattern -> Int -> Double
getActivationProbabilityHidden ws u c v y index
  = activation (getActivationSumHidden ws u c v y index)


-- | @updateNeuron mode ws pat index@ , given a vector @pat@ of type @mode@
-- updates the neuron with number @index@ in the layer with opposite type.
updateNeuronVisible :: MonadRandom m => Weights -> Bias -> Pattern -> Int -> m Int
updateNeuronVisible ws bias h index
  = gibbsSampling $ getActivationProbabilityVisible ws bias h index


updateNeuronHidden :: MonadRandom m => Weights -> Weights ->  Bias -> Pattern -> Pattern -> Int -> m Int
updateNeuronHidden ws u c v y index
  = gibbsSampling $ getActivationProbabilityHidden ws u c v y index


-- | @getCounterPattern mode ws pat@, given a vector @pat@ of type @mode@
-- computes the values of all the neurons in the layer of the opposite type.
updateVisible :: MonadRandom m => Weights -> Bias -> Pattern -> m Pattern
updateVisible ws bias h
  -- | Just e <- validPattern phase mode ws pat = error e
  -- | otherwise
  = V.fromList `liftM` mapM (updateNeuronVisible ws bias h) updatedIndices
    where
      updatedIndices = [0 .. V.length ws - 1]


updateHidden ::  MonadRandom m => Weights -> Weights -> Bias -> Pattern -> Pattern -> m Pattern
updateHidden ws u c v y
  = V.fromList `liftM` mapM (updateNeuronHidden ws u c v y) updatedIndices
    where
      updatedIndices = [0 .. (V.length $ ws ! 0) - 1 ]


-- todo add a validClassification function which checks that there is only one
-- 1 in the class pattern
updateClassification :: Weights -> Bias -> Pattern -> Pattern
updateClassification u d h
  = V.fromList [ if n == new_class then 1 else 0 | n <- all_classes]
    where
      -- TODO replace with actual sampling using inverse method (with cdf list)
      new_class   = maximumBy compare_by_activation_sum all_classes
      compare_by_activation_sum x y = compare (exp_activation x) (exp_activation y)
      exp_activation = exp . (getActivationSum u d h)
      all_classes = [0 .. nr_classes - 1]
      nr_classes  = length all_classes


-- TODO remove code duplication between this and above
getClassificationVector :: [(Pattern, Int)] -> Pattern -> Pattern
getClassificationVector pat_classes pat
  = V.fromList [ if n == pat_class then 1 else 0 | n <- map snd pat_classes]
       where pat_class = fromJust $ lookup pat pat_classes

-- | One step which updates the weights in the CD-n training process.
-- The weights are changed according to one of the training patterns.
-- http://en.wikipedia.org/wiki/Restricted_Boltzmann_machine#Training_algorithm
-- @oneTrainingStep bm visible class@
oneTrainingStep :: MonadRandom m => BoltzmannData -> Pattern ->  m BoltzmannData
oneTrainingStep (BoltzmannData ws u b c d pats nr_h pat_to_class) v = do
  let y     = getClassificationVector pat_to_class v
      h_sum = getHiddenSums ws u c v y
  h        <- updateHidden  ws u c v y
  v'       <- updateVisible ws b h
  let y'   = updateClassification u d h
      (h_sum' :: V.Vector Double) = getHiddenSums ws u c v' y'
  let f    = fromDataVector . fmap fromIntegral
      pos_ws  = NC.toLists $ (f v)  `NC.outer` (fromDataVector h_sum)  -- "positive gradient"
      neg_ws  = NC.toLists $ (f v') `NC.outer` (fromDataVector h_sum')  -- "negative gradient"
      pos_u   = NC.toLists $ (f y)  `NC.outer` (fromDataVector h_sum)   -- "positive gradient"
      neg_u   = NC.toLists $ (f y') `NC.outer` (fromDataVector h_sum')  -- "negative gradient"
      d_ws    = map (map (* learningRate)) $ combine (-) pos_ws neg_ws -- weights delta
      new_ws  = vector2D $ combine (+) (list2D ws) d_ws
      d_u     = map (map (* learningRate)) $ combine (-) pos_u neg_u -- weights delta
      new_u   = vector2D $ combine (+) (list2D ws) d_u
      new_b   = combineVectors (+) b $ V.map ((* learningRate) . fromIntegral) (combineVectors (-) v v')
      new_c   = combineVectors (+) c $ V.map ((* learningRate)) (combineVectors (-) h_sum h_sum')
      new_d   = combineVectors (+) d $ V.map ((* learningRate) . fromIntegral) (combineVectors (-) y y')
  return $ BoltzmannData new_ws new_u new_b new_c new_d pats nr_h pat_to_class


-- | The training function for the Bolzmann Machine.
-- We are using the contrastive divergence algorithm CD-1
-- TODO see if making the vis
-- (we could extend to CD-n, but "In pratice,  CD-1 has been shown to work surprisingly well."
-- @trainBolzmann pats nr_hidden@ where @pats@ are the training patterns
-- and @nr_hidden@ is the number of neurons to be created in the hidden layer.
-- http://en.wikipedia.org/wiki/Restricted_Boltzmann_machine#Training_algorithm
trainBolzmann :: MonadRandom m => [Pattern] -> Int -> m BoltzmannData
trainBolzmann pats nr_h = do
  ws <- vector2D `liftM` genWeights
  u  <- vector2D `liftM` genU
  foldM oneTrainingStep (BoltzmannData ws u b c d pats nr_h pats_classes) pats
    where
      genWeights = replicateM nr_visible . replicateM nr_h $ normal 0.0 0.01
      genU       = replicateM nr_classes . replicateM nr_h $ normal 0.0 0.01
      b  = V.fromList $ replicate nr_visible 0.0
      c  = V.fromList $ replicate nr_h 0.0
      d  = V.fromList $ replicate nr_classes 0.0
      nr_classes = length nub_pats
      nub_pats = nub pats
      pats_classes = [ p_class | p_class <- zip nub_pats [0 .. ] ]
      nr_visible = V.length $ pats !! 0


-- | The activation functiom for the network (the logistic sigmoid).
-- http://en.wikipedia.org/wiki/Sigmoid_function
activation :: Double -> Double
activation x = 1.0 / (1.0 + exp (-x))

softplus :: Double -> Double
softplus x = log (1.0 + exp x)


-- | @validPattern mode weights pattern@
-- Returns an error string in a Just if the @pattern@ is not compatible
-- with @weights@ and Nothing otherwise. @mode@ gives the type of the pattern,
-- which is checked (Visible or Hidden).
validPattern :: Mode -> Weights -> Pattern -> Maybe String
validPattern mode ws pat
  | getDimension mode ws /= V.length pat = Just $ "Size of pattern must match network size in " ++ show mode
  | V.any (\x -> notElem x [0, 1]) pat   = Just "Non binary element in bolzmann pattern"
  | otherwise                            = Nothing


validWeights :: Weights -> Maybe String
validWeights ws
  | V.null ws = Just "The  matrix of weights is empty"
  | V.any (\x -> V.length x /= V.length (ws ! 0)) ws = Just "Weigths matrix ill formed"
  | otherwise = Nothing


matchPatternBoltzmann :: BoltzmannData -> Pattern -> Int
matchPatternBoltzmann bm@(BoltzmannData ws u b c d pats nr_h pats_classes) v
  = fromJust $ max_pat `elemIndex` pats
    where
      patterns_with_energies = [ (p, getFreeEnergy bm v (getClassificationVector pats_classes p)) | p <- pats]
      probability x = exp $ (- x)
      comparePats x y = compare (probability $ snd x) (probability $ snd y)
      max_pat = fst $ maximumBy comparePats patterns_with_energies


getFreeEnergy :: BoltzmannData -> Pattern -> Pattern -> Double
getFreeEnergy (BoltzmannData ws u b c d pats nr_h pats_classes) v y
  = - dotProduct d (fmap fromIntegral y) - sum [ f i | i <- [0 .. nr_h - 1] ]
    where f = softplus . (getActivationSumHidden  ws u c v y)

