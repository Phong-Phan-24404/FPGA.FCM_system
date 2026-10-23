# File: 2_bit_exact_algorithm/profiles.py
# Description: Defines the fixed-point formats and hardware calculation settings.

# Uses 450x450 grayscale frames with K=2..7 clusters.
# Centers use Q8.F, and memberships use unsigned Q0.M with space for 1.0.
# Accumulator widths are calculated to fit valid input frames.
from dataclasses import dataclass, asdict

NPIX = 450 * 450


# Class: Profile
# Description: Stores the numeric formats, rounding rules, and signal widths.
@dataclass(frozen=True)
class Profile:
    name: str
    center_frac: int
    member_frac: int
    norm_guard: int = 16
    accumulation_policy: str = 'post_square_shift'
    epsilon_num: int = 1
    epsilon_den: int = 10

    # Function: __post_init__
    # Description: Checks that the profile settings are supported.
    def __post_init__(self):
        if not (4 <= self.center_frac <= 16 and 6 <= self.member_frac <= 16):
            raise ValueError('invalid Q format')
        if not (8 <= self.norm_guard <= 24):
            raise ValueError('normalizer guard outside supported range')
        if self.accumulation_policy not in ('post_square_shift', 'multiply_before_shift'):
            raise ValueError('unknown accumulation arithmetic')

    # Function: widths
    # Description: Calculates the required bit widths for the datapath.
    @property
    def widths(self):
        f, m = self.center_frac, self.member_frac
        full = 1 << m
        raw_square = (2*m+1)  # the squared membership needs enough bits to hold 2^(2M)
        unrounded_count_square = (NPIX * (full*full)).bit_length()
        w = dict(pixel=8, histogram_count=18, k_selector=3, iteration_counter=8,
                 center=8+f, gray_q=8+f, distance=8+f,
                 distance_square=16+2*f,
                 ratio=m+1, ratio_sum=(7*full).bit_length(),
                 membership=m+1, membership_square=m+1,
                 membership_square_full=raw_square,
                 count_square_product=unrounded_count_square,
                 accumulator_den=(NPIX*full).bit_length(),
                 accumulator_num=(NPIX*full*255).bit_length(),
                 numerator_before_update=(NPIX*full*255).bit_length()+f,
                 ratio_div_numerator=16+2*f+m,
                 normalization_div_numerator=m+self.norm_guard+1,
                 normalization_recip=self.norm_guard+1,
                 normalization_product=m+self.norm_guard+2,
                 label=3, delta=8+f)
        return w

    # Function: epsilon_raw
    # Description: Converts the convergence threshold to a Q8.F value.
    @property
    def epsilon_raw(self):
        # round the threshold to the nearest fixed-point integer
        return ((1<<self.center_frac)*self.epsilon_num + self.epsilon_den//2)//self.epsilon_den

    # Function: describe
    # Description: Returns the profile settings as a dictionary.
    def describe(self) -> dict:
        return dict(**asdict(self), epsilon_raw=self.epsilon_raw, widths=self.widths,
                    contract='FCM_UNSIGNED_RATIO_NORM_V4', max_iter=200,
                    rounding='floor for nonnegative fixed arithmetic; numerator count*U*U shifted once if multiply_before_shift',
                    overflow='forbidden/assert; no wrap in valid domain',
                    duplicate_centers='split Q1 among zero-distance centers, lower index gets remainder',
                    residual_membership='allocate missing LSBs to maximal ratio, lower-index tie',
                    label_tie='lower index',
                    empty_accumulator='reseed from max histogram_count*nearest_square, tie low gray; distinct for multiple dead')


PROFILES = {
    'compact': Profile('compact', center_frac=6, member_frac=12, norm_guard=16),
    'precision': Profile('precision', center_frac=12, member_frac=16, norm_guard=18, accumulation_policy='multiply_before_shift'),
}


# Function: get_profile
# Description: Finds a profile by name and checks that it exists.
def get_profile(name: str) -> Profile:
    if name not in PROFILES:
        raise ValueError(f'profile must be one of {list(PROFILES)}')
    return PROFILES[name]
