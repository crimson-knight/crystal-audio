require "http/client"
require "json"

# Two-stage transcription pipeline:
#   Stage 1: whisper.cpp → raw timestamped transcript
#   Stage 2: LLM (Claude API) → formatted output per recording mode
#
# Mode system prompt examples are included as constants.
# Override by setting pipeline.system_prompt = "your instructions"

module CrystalAudio
  module Transcription
    enum PipelineMode
      Dictation  # Clean up spoken prose/code, remove fillers, fix punctuation
      Meeting    # Produce structured notes: summary, decisions, action items
      Code       # Convert spoken code constructs to correct syntax
    end

    class Pipeline
      CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"

      # Model choices: balance speed vs quality per mode
      DICTATION_MODEL = "claude-haiku-4-5-20251001"   # low latency
      MEETING_MODEL   = "claude-opus-4-6"              # high quality

      property mode          : PipelineMode
      property system_prompt : String?      # override default prompt if set
      property api_key       : String
      property max_tokens    : Int32

      def initialize(
        mode     : PipelineMode = PipelineMode::Dictation,
        api_key  : String = ENV["ANTHROPIC_API_KEY"]? || "",
        max_tokens : Int32 = 2048
      )
        @mode = mode
        @api_key = api_key
        @max_tokens = max_tokens
      end

      # Format an array of whisper segments into polished output.
      # For dictation: call this per utterance (low latency).
      # For meetings: call this once on the full transcript.
      def format(segments : Array(Segment)) : String
        return "" if segments.empty?

        prompt = build_user_prompt(segments)
        system = @system_prompt || default_system_prompt
        model  = (@mode == PipelineMode::Meeting) ? MEETING_MODEL : DICTATION_MODEL

        call_claude(system, prompt, model)
      end

      # Convenience: format raw text (already joined)
      def format(text : String) : String
        format([Segment.new(text, 0_i64, 0_i64)])
      end

      private def build_user_prompt(segments : Array(Segment)) : String
        case @mode
        when PipelineMode::Meeting
          # Include timestamps for meeting notes
          segments.map { |s|
            s.speaker_turn_next ? "[SPEAKER CHANGE]\n#{s.text}" : s.text
          }.join("\n")
        else
          # Plain text for dictation and code modes
          segments.map(&.text).join(" ").strip
        end
      end

      private def default_system_prompt : String
        case @mode
        in PipelineMode::Dictation
          DICTATION_SYSTEM_PROMPT
        in PipelineMode::Meeting
          MEETING_SYSTEM_PROMPT
        in PipelineMode::Code
          CODE_SYSTEM_PROMPT
        end
      end

      private def call_claude(system : String, user_message : String, model : String) : String
        raise "ANTHROPIC_API_KEY not set" if @api_key.empty?

        body = {
          model:      model,
          max_tokens: @max_tokens,
          system:     system,
          messages:   [{"role" => "user", "content" => user_message}]
        }.to_json

        headers = HTTP::Headers{
          "Content-Type"      => "application/json",
          "x-api-key"         => @api_key,
          "anthropic-version" => "2023-06-01"
        }

        response = HTTP::Client.post(CLAUDE_API_URL, headers: headers, body: body)
        raise "Claude API error #{response.status_code}: #{response.body}" unless response.success?

        parsed = JSON.parse(response.body)
        parsed["content"][0]["text"].as_s
      end

      # ── Default system prompts ─────────────────────────────────────────────

      DICTATION_SYSTEM_PROMPT = <<-PROMPT
        You are a dictation cleanup assistant. The user has spoken text and you
        are receiving the raw speech-to-text output. Your job is to:
        - Fix obvious transcription errors (e.g., homophones used incorrectly)
        - Add correct punctuation and capitalization
        - Remove filler words (um, uh, like, you know) unless they seem intentional
        - Preserve paragraph breaks where the speaker paused meaningfully
        - Do NOT add content, elaborate, or change the meaning
        Output only the cleaned text with no commentary or preamble.
      PROMPT

      MEETING_SYSTEM_PROMPT = <<-PROMPT
        You are a meeting notes assistant. You will receive a raw transcript
        of a meeting. Produce structured meeting notes with these sections:

        ## Summary
        2-3 sentence overview of what was discussed.

        ## Key Discussion Points
        Bullet points of the main topics, in order of discussion.

        ## Decisions Made
        Bullet list of decisions reached. Write "None recorded." if none.

        ## Action Items
        Each action item: "- [Owner if known] Action (by deadline if mentioned)"

        ## Open Questions
        Questions raised but not resolved.

        Rules:
        - Do not invent details not present in the transcript
        - Note unclear sections with [unclear]
        - Attribute to [SPEAKER CHANGE] markers if present
      PROMPT

      CODE_SYSTEM_PROMPT = <<-PROMPT
        You are a technical dictation assistant. The user is dictating code,
        technical documentation, or developer notes. Your job is to:
        - Convert spoken programming constructs to correct syntax
          (e.g., "def foo open paren bar close paren" → "def foo(bar)")
        - Format code blocks with appropriate fencing (```language)
        - Fix speech-to-text errors in technical terms
        - Preserve technical precision — do not paraphrase technical statements
        - For prose sections: clean up punctuation and remove fillers
        Output only the cleaned text/code with no commentary.
      PROMPT
    end
  end
end
