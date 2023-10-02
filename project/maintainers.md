<!-- vim: filetype=markdown colorcolumn=80
-->

# Maintainers handbook

This document is a guide for maintainers across the spire/helm-chart effort to
provide a consistent user interface for those going through the review process.

## The Pull Request

Pull requests are submitted through GitHub. They are contributions to change
the project. There is no difference between code and non-code submissions, in
procedure or policy.

All maintainers should consider that pull requests are gifts. The project
survives due to the effort of frequent contributors and their generosity. As
such, to encourage future submissions, the default approach to handling a merge
request should be gratitude, even if the request cannot be merged.

## Roles

There are two primary roles within the scope of a pull request.

- Committer - one who offers code to be merged.
- Maintainer - one who merges the code.

To ensure that all code receives a proper review, these roles are mutually
exclusive for each pull request. Within the scope of a pull request, a
Committer cannot be a Maintainer, nor can a Maintainer be a Committer.

For abandoned pull requests still requiring work, or efforts transferred between
people, a Maintainer may become a Committer, invalidating any of their prior
review work. 

### Committers

Committers are people contributing changes to the repository. The first
committer is typically the one that opens the pull request. Additional people
can become committers in the same merge request if they change the pull request
directly.

Suggestions to a committer by a maintainer, such as commentary that with a
change the merge request might be accepted, does not make a maintainer a
committer, as the committer will choose to include the change at their discretion.

### Maintainers

Maintainers hold a dual role in the project. They are ambassadors of the
effort as well as the gatekeepers permitting changes to the repository. As
ambassadors, maintainers must present a fair and impartial demeanor when
dealing with contributors.

Failure to be fair or impartial reflects poorly on the released product, as
guilt by association taints the product. The process of reviewing a merge
request often includes conflict. Contributors can become defensive about work
they've done while maintainers can become adamant in the changes they request.

To prevent a breakdown in the review process, the project encourages all
reviewers to adhere to a standard set of review best practices. Reviewers
should familiarize themselves with these practices and suggest updates to keep
the practices relevant over time.

## Review Standards

These standards serve to prevent problems from cropping up during a review. The 
intent is that consistent application of these standards permits a consistent 
review process, leading to repeatable, suprise free, outcomes during a review.

The intent of maintaining standards is to enhance productivity and improve team
morale. In the event the standards have a negative impact on productivity or
morale, the standard itself should be questioned. To clarify the kinds of
productivity to be improved, the intent is to reduce the time between initial
submission of a merge request and its resolution.

### Challenges to the Review Process

Whenever possible, a maintainer should not argue a point about the review
standards with a contributor. Instead they should provide this document to the
contributor, indicating that changes to the review process are to be initiated
with a standard-altering Issue.

In the exceedingly rare situation that a reviewer opts to ignore a review
standard during a merge request, the reviewer must indicate they are purposefully
ignoring the standard and the reason why. There are valid reasons to ignore
standards, but whenever possible a maintainer should uphold the standard or
change it.

### Review Outcomes

From the Maintainers point of view, all merge requests require one of four
actions:

- The maintainer accepts the pull request.
- The maintainer rejects the pull request.
- The maintainer requests the pull request be altered.
- The maintainer rewrites some or all of the pull request, becoming a
  committer.

Suggestions to the committer that a merge request be altered do not constitute
becoming an committer, even if the maintainer provides the lines of code
being suggested.

### Review Tempo

Maintainers should set aside and appropriate amount of time when reviewing. The
initial suggestion is one hour. Most reviews will complete well under this time,
but a few will take longer. Longer reviews should include review breaks, so the
reviewer remains fresh and attentive. Attempting a three hour long review often
yields worse results than two or three shorter efforts with breaks.

The concept of going slow to complete items quickly is not a new one. With a
little extra time, comments can be thoughtful instead of reactive.

### Review Goals

Each review should have a defined set of goals established prior to the main
work of the review. The review process often challenges the committer, in the
hopes of improving the merge request. Keeping the review scoped to goals avoids
scenarios where the reviewer's requests seem capricious or autocratic.

The current list of review goals include:

- Keeping the code base readable
- Keeping the code base search-able
- Keeping the code base understandable
- Keeping the code base maintainable
- Keeping the code base testable
- Keeping the code base functional

Note that quality, stability, and robustness are purposefully not included in
this list: 

- Quality is the combination of readable and testable.
- Stability is the combination of understandable, functional, and testable.
- Robustness is the combination of maintainable, functional, and testable.

Code standards are being developed to clarify specific tests to support these
goals.

### Developer Testing prior to Review

Each submission should assume that the committer ran the unit tests and 
small-scale (not requiring an environment) integration tests prior to submission.
The merge request CI pipeline also runs these tests automatically. Failure to
pass them leads to an automatic call for merge request modification.

Attempts to pass this requirement by disabling tests or modifying them such that
they are effectively disabled are strongly discouraged. They violate the review
goals by reducing maintainability (no new failures will be detected) and
possibly functionality (for scenarios outside of the current mindset).

At their leisure, maintainers may suggest code changes to make the test suite pass.
Doing so is never required, nor part of the minimum duties of a maintainer.

### Reviewer Count

Two passing reviews are required for code to be merged. 

Whenever possible, the number of reviewers should be limited, as each additional
reviewer presents an extra set of communication channels between the review and
themselves. 

- One reviewer has one channel between the committer and the reviewer
- Increasing to two, adds one channel to the the committer, and one to the 
  reviewers.
- Increasing to three, adds one channel to the committer, and two to the
  reviewers.
- Increasing to four, adds one channel to the committer, and three to the
  reviewers.

The amount of possible communication grows such that 
`commChannels(reviewers) = reviewers + reviewers(reviewers-1)/2` leads to an 
`O(n^2)` number of channels. Thus, keeping reviewer count low is critical to
velocity.

### Reviewer Consensus

Reviewers should coordinate among themselves when differences of opinion arise
in a review. The first reviewer is likely to make a statement before being
aware of the difference of opinion; but, once a difference of opinion is known,
the reviewers should coordinate privately to find a unified presentation of the
desired features to communicate back to the committer.

The committer has no role in the evaluation of options to determine the proper
path forward, including them only diminishes the efficiency of the process and
increases the stress they endure while they observe the discussion. Once a path
is agreed upon:

- If the request to the committer was reversed, the reviewer making that stance
  should present the new path.
- If the request to the committer was refined, the second reviewer should 
  present the refined path.

If no path forward can be agreed upon, the proposed path that is closest to the
committer submission is the accepted path. This guideline exists to promote
cooperation among reviewers. Ideas of merit which don't become part of the
merge request should be submitted as new issues and reviewed independently.

### Review Automation

Reviewers have a commitment to continuous improvement of the review process.
Whenever a reviewer sees an opportunity to reduce the manpower involved in the
review process by automating a portion of the process, the reviewer should
create an issue and submit it as an improvement to the CI process.

Improvements are subject to the same review process and the same review goals
as other committer offerings. Readability, search-ability, understanding,
maintenance, testing, and functionality are goals of the review process just as
they are of the product code. 

Lack of speed in the review process is viewed as a failure to make the process
maintainable, understandable, and functional.

### Review Communication

Reviewers are encouraged to have meaningful dialogues with contributors and
reviewers during a merge request. For these dialogues to be effective, the
purpose of each communication should be considered. Mixing purposes in
communication creates problems in understanding intent, retarding progress.
Scope your communications to move efforts forward.

Avoid mixing the following communication scopes:

- Status update
- Decision making
- Problem solving
- Team building
- Information sharing
- Brainstorming

Combining these scopes reduce the effectiveness of the communication. Ideally
they should be done in different settings. Mixing a brainstorming session with
a decision making session disrupts the evaluation of pros and cons with new
options. Attempting to problem solve a technical issue during a status update
draws focus away from identifying the challenges of delivering the project,
replacing them with the challenges of solving a single problem in the project.

