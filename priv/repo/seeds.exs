alias Chorus.{Boards, Ideas}

# Create the default board
{:ok, board} =
  Boards.create_board(%{
    title: "ML Root Problems",
    description: "A community board for exploring fundamental problems in machine learning. Submit ideas for projects that tackle core ML challenges.",
    owner_id: "github:dev-user-1"
  })

IO.puts("Created board: #{board.title} (#{board.id})")

# Seed some example ideas
ideas = [
  %{
    title: "Build a benchmark suite for gradient estimation methods",
    description: "Compare finite differences, REINFORCE, straight-through estimators, and newer methods across standard optimization landscapes. Output a reproducible leaderboard.",
    tags: ["optimization", "benchmarks"]
  },
  %{
    title: "Investigate catastrophic forgetting in small language models",
    description: "Train a series of small (<100M param) LMs on sequential tasks and measure forgetting with different mitigation strategies (EWC, PackNet, replay buffers).",
    tags: ["continual-learning", "nlp"]
  },
  %{
    title: "Minimal reproduction of grokking in modular arithmetic",
    description: "Reproduce the grokking phenomenon from the Power et al. paper with clean, minimal code. Explore which architectural choices affect time-to-grok.",
    tags: ["generalization", "interpretability"]
  },
  %{
    title: "Survey and implement loss landscape visualization techniques",
    description: nil,
    tags: ["visualization", "optimization"]
  },
  %{
    title: "Create a dataset of ML paper claims vs. reproduction outcomes",
    description: "Systematically collect claims from top ML papers and match them against reproduction attempts. Could become a useful resource for the community.",
    tags: ["reproducibility", "meta-science"]
  }
]

for {attrs, idx} <- Enum.with_index(ideas) do
  {:ok, idea} =
    Ideas.create_idea(
      Map.merge(attrs, %{
        submitted_by_user_id: "dev-user-#{rem(idx, 3) + 1}",
        submitted_by_provider: "github",
        submitted_by_display_name: Enum.at(["Dev User", "Alice", "Bob"], rem(idx, 3)),
        board_id: board.id
      })
    )

  # Add some upvotes to make it interesting
  upvote_count = Enum.at([7, 12, 5, 3, 9], idx)

  for i <- 1..upvote_count do
    Ideas.create_upvote(idea.id, "anon:seed:voter-#{i}")
  end

  IO.puts("  Created #{idea.identifier}: #{idea.title} (#{upvote_count} upvotes)")
end

IO.puts("\nDone! Visit http://localhost:4000 to see the board.")
