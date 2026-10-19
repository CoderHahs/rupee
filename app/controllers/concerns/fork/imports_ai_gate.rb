# Prepended to ImportsController (design §4.10). PDF and document imports
# send the file to the AI provider, so with the household switch off the
# upload is refused up front rather than failing later in a job.
module Fork::ImportsAiGate
  private
    def create_pdf_import(file)
      return refuse_ai_import unless Current.family.household_ai_enabled?

      super
    end

    def create_document_import(file)
      return refuse_ai_import unless Current.family.household_ai_enabled?

      super
    end

    def refuse_ai_import
      redirect_to new_import_path, alert: I18n.t("fork.imports.ai_off")
    end
end
