# Copyright (c) 2023, NVIDIA CORPORATION & AFFILIATES.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


from typing import List, Tuple
from collections import defaultdict

def substitute_replacements_in_text(
    text: str, replacements: List[Tuple[int, int, str, float]], replace_hyphen_to_space: bool
) -> str:
    """Substitute replacements to the input text, iterating from end to beginning, so that indexing does not change.
       Note that we expect intersecting replacements to be already filtered.
    Args:
        text: sentence;
        replacements: list of replacements, each is a tuple (begin, end, text, probability);
        replace_hyphen_to_space: if True, hyphens in replacements will be converted to spaces;
    Returns:
        corrected sentence
    """
    replacements.sort()
    last_begin = len(text) + 1
    corrected_text = text
    for begin, end, candidate, prob in reversed(replacements):
        if end > last_begin:
            print("WARNING: skip intersecting replacement [", candidate, "] in text: ", text)
            continue
        if replace_hyphen_to_space:
            candidate = candidate.replace("-", " ")
        corrected_text = corrected_text[:begin] + candidate + corrected_text[end:]
        last_begin = begin
    return corrected_text

def apply_replacements_to_text(
    text: str,
    replacements: List[Tuple[int, int, str, float]],
    min_prob: float = 0.5,
    replace_hyphen_to_space: bool = False,
    dp_data: Tuple[defaultdict, defaultdict, defaultdict, int] = None,
    min_dp_score_per_symbol: float = -99.9,
) -> str:
    """Filter and apply replacements to the input sentence.
    Args:
        text: input sentence;
        replacements: list of proposed replacements (probably intersecting), each is a tuple (begin, end, text, probability);
        min_prob: threshold on replacement probability;
        replace_hyphen_to_space: if True, hyphens in replacements will be converted to spaces;
        dp_data: n-gram mapping vocabularies used by dynamic programming, if None - dynamic programming is not used;
        min_dp_score_per_symbol: threshold on dynamic programming sum score averaged by hypothesis length
    Returns:
        corrected sentence
    """
    # sort replacements by positions
    replacements.sort()
    # filter replacements
    # Note that we do not skip replacements with same text, otherwise intersecting candidates with lower probability can win
    filtered_replacements = []
    for j in range(len(replacements)):
        replacement = replacements[j]
        begin, end, candidate, prob = replacement
        fragment = text[begin:end]
        candidate_spaced = " ".join(list(candidate.replace(" ", "_")))
        fragment_spaced = " ".join(list(fragment.replace(" ", "_")))
        # apply penalty if candidate length is bigger than fragment length
        # to avoid cases like "forward-looking" replacing "looking" in "forward looking" resulting in "forward forward looking"
        if len(candidate) > len(fragment):
            penalty = len(fragment) / len(candidate)
            prob *= penalty
        # skip replacement with low probability
        if prob < min_prob:
            continue
        # skip replacements with some predefined templates, e.g. "*'s" => "*s"
        if check_banned_replacements(fragment, candidate):
            continue
        if dp_data is not None:
            path = get_alignment_by_dp(candidate_spaced, fragment_spaced, dp_data)
            # path[-1][3] is the sum of logprobs for best path of dynamic programming: divide sum_score by length
            if path[-1][3] / (len(fragment)) < min_dp_score_per_symbol:
                continue

        # skip replacement if it intersects with previous replacement and has lower probability, otherwise remove previous replacement
        if len(filtered_replacements) > 0 and filtered_replacements[-1][1] > begin:
            if filtered_replacements[-1][3] > prob:
                continue
            else:
                filtered_replacements.pop()
        filtered_replacements.append((begin, end, candidate, prob))

    return substitute_replacements_in_text(text, filtered_replacements, replace_hyphen_to_space)

def check_banned_replacements(src: str, dst: str) -> bool:
    """This function is used to check is a pair of words/phrases is matching some common template that we don't want to replace with one another.
    Args:
        src: first phrase
        dst: second phrase
    Returns True if this replacement should be banned.
    """
    # customers' => customer's
    if src.endswith("s'") and dst.endswith("'s") and src[0:-2] == dst[0:-2]:
        return True
    # customer's => customers'
    if src.endswith("'s") and dst.endswith("s'") and src[0:-2] == dst[0:-2]:
        return True
    # customers => customer's
    if src.endswith("s") and dst.endswith("'s") and src[0:-1] == dst[0:-2]:
        return True
    # customer's => customers
    if src.endswith("'s") and dst.endswith("s") and src[0:-2] == dst[0:-1]:
        return True
    # customers => customers'
    if src.endswith("s") and dst.endswith("s'") and src[0:-1] == dst[0:-2]:
        return True
    # customers' => customers
    if src.endswith("s'") and dst.endswith("s") and src[0:-2] == dst[0:-1]:
        return True
    # utilities => utility's
    if src.endswith("ies") and dst.endswith("y's") and src[0:-3] == dst[0:-3]:
        return True
    # utility's => utilities
    if src.endswith("y's") and dst.endswith("ies") and src[0:-3] == dst[0:-3]:
        return True
    # utilities => utility
    if src.endswith("ies") and dst.endswith("y") and src[0:-3] == dst[0:-1]:
        return True
    # utility => utilities
    if src.endswith("y") and dst.endswith("ies") and src[0:-1] == dst[0:-3]:
        return True
    # group is => group's
    if src.endswith(" is") and dst.endswith("'s") and src[0:-3] == dst[0:-2]:
        return True
    # group's => group is
    if src.endswith("'s") and dst.endswith(" is") and src[0:-2] == dst[0:-3]:
        return True
    # trex's => trex
    if src.endswith("'s") and src[0:-2] == dst:
        return True
    # trex => trex's
    if dst.endswith("'s") and dst[0:-2] == src:
        return True
    # increases => increase (but trimass => trimas is ok)
    if src.endswith("s") and (not src.endswith("ss")) and src[0:-1] == dst:
        return True
    # increase => increases ((but trimas => trimass is ok))
    if dst.endswith("s") and (not dst.endswith("ss")) and dst[0:-1] == src:
        return True
    # anticipate => anticipated
    if src.endswith("e") and dst.endswith("ed") and src[0:-1] == dst[0:-2]:
        return True
    # anticipated => anticipate
    if src.endswith("ed") and dst.endswith("e") and src[0:-2] == dst[0:-1]:
        return True
    # blocks => blocked
    if src.endswith("s") and dst.endswith("ed") and src[0:-1] == dst[0:-2]:
        return True
    # blocked => blocks
    if src.endswith("ed") and dst.endswith("s") and src[0:-2] == dst[0:-1]:
        return True
    # lives => lived
    if src.endswith("es") and dst.endswith("ed") and src[0:-2] == dst[0:-2]:
        return True
    # lived => lives
    if src.endswith("ed") and dst.endswith("es") and src[0:-2] == dst[0:-2]:
        return True
    # regarded => regard
    if src.endswith("ed") and src[0:-2] == dst:
        return True
    # regard => regarded
    if dst.endswith("ed") and dst[0:-2] == src:
        return True
    # regardeding => regard
    if src.endswith("ing") and src[0:-3] == dst:
        return True
    # regard => regarding
    if dst.endswith("ing") and dst[0:-3] == src:
        return True
    # longer => long
    if src.endswith("er") and src[0:-2] == dst:
        return True
    # long => longer
    if dst.endswith("er") and dst[0:-2] == src:
        return True
    # discussed => discussing
    if src.endswith("ed") and dst.endswith("ing") and src[0:-2] == dst[0:-3]:
        return True
    # discussing => discussed
    if src.endswith("ing") and dst.endswith("ed") and src[0:-3] == dst[0:-2]:
        return True
    # live => living
    if src.endswith("e") and dst.endswith("ing") and src[0:-1] == dst[0:-3]:
        return True
    # living => live
    if src.endswith("ing") and dst.endswith("e") and src[0:-3] == dst[0:-1]:
        return True
    # discussion => discussing
    if src.endswith("ion") and dst.endswith("ing") and src[0:-3] == dst[0:-3]:
        return True
    # discussing => discussion
    if src.endswith("ing") and dst.endswith("ion") and src[0:-3] == dst[0:-3]:
        return True
    # alignment => aligning
    if src.endswith("ment") and dst.endswith("ing") and src[0:-4] == dst[0:-3]:
        return True
    # aligning => alignment
    if src.endswith("ing") and dst.endswith("ment") and src[0:-3] == dst[0:-4]:
        return True
    # dispensers => dispensing
    if src.endswith("ers") and dst.endswith("ing") and src[0:-3] == dst[0:-3]:
        return True
    # dispensing => dispensers
    if src.endswith("ing") and dst.endswith("ers") and src[0:-3] == dst[0:-3]:
        return True
    # integrate => integrity
    if src.endswith("ate") and dst.endswith("ity") and src[0:-3] == dst[0:-3]:
        return True
    # integrity => integrate
    if src.endswith("ity") and dst.endswith("ate") and src[0:-3] == dst[0:-3]:
        return True
    # discussion => discussed
    if src.endswith("ion") and dst.endswith("ed") and src[0:-3] == dst[0:-2]:
        return True
    # discussed => discussion
    if src.endswith("ed") and dst.endswith("ion") and src[0:-2] == dst[0:-3]:
        return True
    # anticipation => anticipate
    if src.endswith("ion") and dst.endswith("e") and src[0:-3] == dst[0:-1]:
        return True
    # anticipate => anticipation
    if src.endswith("e") and dst.endswith("ion") and src[0:-1] == dst[0:-3]:
        return True
    # incremental => increment
    if src.endswith("ntal") and dst.endswith("nt") and src[0:-4] == dst[0:-2]:
        return True
    # increment => incremental
    if src.endswith("nt") and dst.endswith("ntal") and src[0:-2] == dst[0:-4]:
        return True
    # national => nation
    if src.endswith("nal") and dst.endswith("n") and src[0:-3] == dst[0:-1]:
        return True
    # nation => national
    if src.endswith("n") and dst.endswith("nal") and src[0:-1] == dst[0:-3]:
        return True
    # significantly => significant
    if src.endswith("ntly") and dst.endswith("nt") and src[0:-4] == dst[0:-2]:
        return True
    # significant => significantly
    if src.endswith("nt") and dst.endswith("ntly") and src[0:-2] == dst[0:-4]:
        return True
    # delivery => deliverer
    if src.endswith("ery") and dst.endswith("erer") and src[0:-3] == dst[0:-4]:
        return True
    # deliverer => delivery
    if src.endswith("erer") and dst.endswith("ery") and src[0:-4] == dst[0:-3]:
        return True
    # deliver => deliverer
    if src.endswith("er") and dst.endswith("erer") and src[0:-2] == dst[0:-4]:
        return True
    # deliverer => deliver
    if src.endswith("erer") and dst.endswith("er") and src[0:-4] == dst[0:-2]:
        return True
    # comparably => comparable
    if src.endswith("bly") and dst.endswith("ble") and src[0:-3] == dst[0:-3]:
        return True
    # comparable => comparably
    if src.endswith("ble") and dst.endswith("bly") and src[0:-3] == dst[0:-3]:
        return True
    # comparably => comparability
    if src.endswith("bly") and dst.endswith("bility") and src[0:-3] == dst[0:-6]:
        return True
    # comparability => comparably
    if src.endswith("bility") and dst.endswith("bly") and src[0:-6] == dst[0:-3]:
        return True
    # beautiful => beautifully
    if src.endswith("l") and dst.endswith("lly") and src[0:-1] == dst[0:-3]:
        return True
    # beautifully => beautiful
    if src.endswith("lly") and dst.endswith("l") and src[0:-3] == dst[0:-1]:
        return True
    # active => actively
    if src.endswith("e") and dst.endswith("ely") and src[0:-1] == dst[0:-3]:
        return True
    # actively => active
    if src.endswith("ely") and dst.endswith("e") and src[0:-3] == dst[0:-1]:
        return True
    # america => american
    if src.endswith("a") and dst.endswith("an") and src[0:-1] == dst[0:-2]:
        return True
    # american => america
    if src.endswith("an") and dst.endswith("a") and src[0:-2] == dst[0:-1]:
        return True
    # reinvesting => investing
    if src.startswith("re") and src[2:] == dst:
        return True
    # investing => reinvesting
    if dst.startswith("re") and dst[2:] == src:
        return True
    # unchanged => changed
    if src.startswith("un") and src[2:] == dst:
        return True
    # changed => unchanged
    if dst.startswith("un") and dst[2:] == src:
        return True
    # disrespected => respected
    if src.startswith("dis") and src[3:] == dst:
        return True
    # respected => disrespected
    if dst.startswith("dis") and dst[3:] == src:
        return True
    # outperformance => performance
    if src.startswith("out") and src[3:] == dst:
        return True
    # performance => outperformance
    if dst.startswith("out") and dst[3:] == src:
        return True
    return False
