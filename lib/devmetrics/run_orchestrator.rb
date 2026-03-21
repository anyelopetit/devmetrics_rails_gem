module Devmetrics
  class RunOrchestrator
    SPEC_GLOB = "spec/requests/**/*_spec.rb"

    def self.call
      new.call
    end

    def call
      file_paths = discover_files
      return { error: "No request specs found in #{SPEC_GLOB}" } if file_paths.empty?

      run = ::Devmetrics::Run.create_for_files(file_paths)

      file_metas = file_paths.map do |path|
        file_key = ::Devmetrics::FileResult.file_key_for(path)
        ::Devmetrics::FileResult.create!(
          run_id:    run.run_id,
          file_key:  file_key,
          file_path: path,
          status:    :pending
        )
        { file_key: file_key, file_path: path, display_name: path.sub(Rails.root.to_s + "/", "") }
      end

      ActionCable.server.broadcast(
        "devmetrics:run:#{run.run_id}",
        { type: "run_started", run_id: run.run_id, files: file_metas }
      )

      file_metas.each do |meta|
        ::Devmetrics::FileRunnerJob.perform_later(
          run_id:    run.run_id,
          file_path: meta[:file_path],
          file_key:  meta[:file_key]
        )
      end

      { run_id: run.run_id, file_count: file_metas.size, files: file_metas }
    end

    private

    def discover_files
      all = Dir.glob(Rails.root.join(SPEC_GLOB)).sort

      tagged = all.select { |f| File.read(f).match?(/devmetrics/i) }
      tagged.any? ? tagged : all
    end
  end
end
