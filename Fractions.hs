import Data.Coerce
import Data.Function (on)
import Data.Ratio
import GHC.Real (Ratio(..))

-- | The (lazy) continued fraction:
--
-- @
-- [a0;a1,a2,a3,a3..an]
-- @
--
-- that represents
--
-- @
-- a0 + 1/(a1 + 1/(a2 + 1/(a3 + .. 1/(a_n))))
-- @
--
-- is given by 
--
-- @
-- CF [a0,a1,a2,a3..an]
-- @
--
-- Coefficients @a1..an@ are all strictly positive. a0 may be 0.
--
-- However, only non-negative continued fractions can be represented this way.
--
-- Negative continued fractions
--
-- @
-- -[a0;a1,a2,a3..an]
-- @
--
-- are represented by
--
-- @
-- CF [-a0,-a1,-a2,-a3..an]
-- @
--
-- The empty list or termination of a list represents an infinite coefficient.
--
-- This is consistent with the notion that truncating a continued fraction
-- is done by adding @1 / (a_n + 1/...)@  -- which needs to be 0, which happens
-- when @a_n@ is infinity.
--
-- This yields the following invariant.
--
-- All coefficients are negative or all coefficients are positive, after a possible
-- leading zero.
--
-- This matches the defacto operation of the Mathematica ContinuedFraction[x,n] combinator,
-- which actually disagrees with the MathWorld description of its operation.

newtype CF = CF { coefs :: [Integer] }
  deriving Show

infinity :: CF
infinity = CF []

instance Eq CF where
  as == bs = compare as bs == EQ

cmp :: [Integer] -> [Integer] -> Ordering
cmp []     []     = EQ
cmp _      []     = LT
cmp []     _      = GT
cmp (a:as) (b:bs) = case compare a b of
  LT -> LT
  EQ -> cmp bs as -- swap sense
  GT -> GT

instance Ord CF where
  -- TODO: normalize
  compare (CF as) (CF bs) = cmp as bs

-- | Euler's constant.
exp' :: CF
exp' = CF $ 2:1:k 2 where k n = n:1:1:k (n + 2)

-- | The golden ratio, aka, the "most irrational number".
phi :: CF
phi = CF ones where ones = 1:ones

-- | Compute a series of convergents, which alternate between optimal conservative approximations above and below to the actual answer, in increasing order by |denominator|, such that given the denominator any rational that lies closer to the real answer must have a larger denominator.
convergents  :: Fractional a => CF -> [a]
convergents (CF xs0) = go 1 0 0 1 xs0 where
  go a b c d [] = []
  go a b c d (y:ys) = fromRational (e :% f) : go e a f c ys
    where e = a*y+b; f = c*y+d

-- | 
-- @
-- z = hom a b c d
-- @
-- 
-- represents an homographic equation of the form
--
-- @
-- z = ax + b
--     ------
--     cx + d
-- @
--
-- with integer coefficients.
--
-- TODO: detect cycles, once we do, detect cycle length, then our position in it
-- this will let us detect the length of the cycle we emit.
hom :: Integer -> Integer -> Integer -> Integer -> CF -> CF
hom = coerce hom'

hom' :: Integer -> Integer -> Integer -> Integer -> [Integer] -> [Integer]
hom' 1 0 0 1 xs = xs
hom' _ _ 0 0 _  = []
hom' a b c d xs
  | c /= 0, d /= 0
  , q <- quot a c, q == quot b d
  = q : hom' c d (a - c*q) (b - d*q) xs
  | otherwise = case xs of
    []   -> hom' a a c c []
    y:ys -> hom' (a*y+b) a (c*y+d) c ys

-- | Gosper-style bihomographic transformations
--
-- @
-- z = axy + bx + cy + d
--     -----------------
--     exy + fx + gy + h
-- @
--
-- TODO: detect cycles
bihom :: Integer -> Integer -> Integer -> Integer
      -> Integer -> Integer -> Integer -> Integer -> CF -> CF -> CF
bihom = coerce bihom 

bihom' :: Integer -> Integer -> Integer -> Integer
   -> Integer -> Integer -> Integer -> Integer -> [Integer] -> [Integer] -> [Integer]
bihom' a b _ _ e f _ _ xs [] = hom' a b e f xs
bihom' a _ c _ e _ g _ [] ys = hom' a c e g ys
bihom' 0 1 0 0 0 0 0 1 xs _  = xs
bihom' 0 0 1 0 0 0 0 1 _  ys = ys
bihom' a b c d e f g h xs@(x:xs') ys@(y:ys')
   | e /= 0, f /= 0, g /= 0, h /= 0 
   , q <- quot a e, q == quot b f
   , q == quot c g, q == quot d h
   = q : bihom' e f g h (a-q*e) (b-q*f) (c-q*g) (d-q*h) xs ys
   | e /= 0 || f /= 0
   , (e == 0 && g == 0) || abs (g*e*b - g*a*f) > abs (f*e*c - g*a*f)
   = bihom' (a*x+b) a (c*x+d) c (e*x+f) e (g*x+h) g xs' ys
   | otherwise
   = bihom' (a*y+c) (b*y+d) a b (e*y+g) (f*y+h) e f xs ys'

-- | Brent's teleporting turtle
brent :: Eq a => [a] -> Bool
brent [] = False
brent (x:xs) = go 1 2 x xs where
  go :: Eq a => Int -> Int -> a -> [a] -> Bool
  go k n t [] = False
  go k n t (r:rs) = r == t || if k == n
    then go 1 (n * 2) r rs
    else go (k + 1) n t rs

instance Num CF where
  (+) = bihom
    0 1 1 0
    0 0 0 1    -- (x+y)/1
  (-) = bihom
    0 1 (-1) 0
    0 0 0    1 -- (x-y)/1
  (*) = bihom
    1 0 0 0
    0 0 0 1    -- (x*y)/1
  negate (CF xs)      = CF (map negate xs) -- hom (-1) 0 0 1 -- -x/1 
  abs (CF as)         = CF (map abs as)
  signum (CF [])      = CF [1]
  signum (CF [0])     = CF [0]
  signum (CF (0:x:_)) = CF [signum x]
  signum (CF (x:_))   = CF [signum x]
  fromInteger n       = CF [n]

instance Fractional CF where
  recip (CF (0:as)) = CF as
  recip (CF as) = CF (0:as)
  (/) = bihom
     0 1 0 0
     0 0 1 0 -- x/y
  fromRational (k0 :% n0) = CF (go k0 n0) where
    go k 0 = []
    go k n = case k `quotRem` n of
      (q, r) -> q : if r == 0
        then []
        else go n r

instance Enum CF where
  succ = hom 1 1 0 1    -- (x+1)/1
  pred = hom 1 (-1) 0 1 -- (x-1)/1
  fromEnum (CF (n:_)) = fromIntegral n
  fromEnum (CF [])    = maxBound
  toEnum = fromIntegral

{-
-- | Compute a homographic equation with continued fraction coefficients.
cfhom :: CF -> CF -> CF -> CF -> [CF] -> [CF]
cfhom 1 0 0 1 xs = xs
cfhom _ _ 0 0 _  = []
cfhom a b c d xs 
  | c /= 0, d /= 0
  , q <- quot a c
  , q == quot b d


-- | the moment two subsequent rationals are have a given integer residue we stop?
properFraction' :: CF -> (Integer, CF)
properFraction (CF []) = (0, CF [])
properFraction' (CF (a:as)) = case compare a 0 of
  LT -> (a - 1, hom (-1) 1 0 1 (0:as))
  EQ -> case as of
    [] -> (0,0)
    (b:bs) | b < 0 -> -- negative 
           | b > 0 -> positive
  GT -> (a, CF (0:as))
-}
