use crate::state::ExportFormat;
use std::io::Write;
use anyhow::Result;
use std::path::Path;
use tokio::fs;
use tokio::io::AsyncWriteExt;

pub struct ExportManager;

impl ExportManager {
    pub fn new() -> Self {
        Self
    }
    
    pub async fn export(
        &self,
        conversation_ids: &[String],
        format: ExportFormat,
        output_path: impl AsRef<Path>,
    ) -> Result<()> {
        let output_path = output_path.as_ref();
        
        // Ensure output directory exists
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent).await?;
        }
        
        match format {
            ExportFormat::Markdown => self.export_markdown(conversation_ids, output_path).await,
            ExportFormat::Json => self.export_json(conversation_ids, output_path).await,
            ExportFormat::Html => self.export_html(conversation_ids, output_path).await,
            ExportFormat::Pdf => self.export_pdf(conversation_ids, output_path).await,
            ExportFormat::Zip => self.export_zip(conversation_ids, output_path).await,
        }
    }
    
    async fn export_markdown(&self, ids: &[String], path: &Path) -> Result<()> {
        let mut content = String::new();
        
        content.push_str("# Claude Conversations Export\n\n");
        content.push_str(&format!("Exported: {}\n\n", chrono::Local::now().format("%Y-%m-%d %H:%M:%S")));
        content.push_str("---\n\n");
        
        for id in ids {
            // In production, load actual conversation content
            content.push_str(&format!("## Conversation: {}\n\n", id));
            content.push_str("*Content would be loaded here*\n\n");
            content.push_str("---\n\n");
        }
        
        let mut file = fs::File::create(path).await?;
        file.write_all(content.as_bytes()).await?;
        
        Ok(())
    }
    
    async fn export_json(&self, ids: &[String], path: &Path) -> Result<()> {
        let conversations: Vec<serde_json::Value> = ids
            .iter()
            .map(|id| {
                serde_json::json!({
                    "id": id,
                    "exported_at": chrono::Local::now().to_rfc3339(),
                    // In production, include actual conversation data
                })
            })
            .collect();
        
        let json = serde_json::json!({
            "export_version": "1.0",
            "exported_at": chrono::Local::now().to_rfc3339(),
            "conversation_count": ids.len(),
            "conversations": conversations,
        });
        
        let content = serde_json::to_string_pretty(&json)?;
        let mut file = fs::File::create(path).await?;
        file.write_all(content.as_bytes()).await?;
        
        Ok(())
    }
    
    async fn export_html(&self, ids: &[String], path: &Path) -> Result<()> {
        let mut html = String::new();
        
        html.push_str("<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n");
        html.push_str("    <meta charset=\"UTF-8\">\n");
        html.push_str("    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n");
        html.push_str("    <title>Claude Conversations Export</title>\n");
        html.push_str("    <style>\n");
        html.push_str("        body { font-family: system-ui, -apple-system, sans-serif; max-width: 900px; margin: 0 auto; padding: 20px; }\n");
        html.push_str("        .conversation { border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin: 20px 0; }\n");
        html.push_str("        .header { background: #f5f5f5; padding: 10px; border-radius: 4px; margin-bottom: 15px; }\n");
        html.push_str("        .message { margin: 10px 0; padding: 10px; border-left: 3px solid #007bff; }\n");
        html.push_str("        .user { border-color: #28a745; background: #f0f9ff; }\n");
        html.push_str("        .assistant { border-color: #6c757d; background: #f8f9fa; }\n");
        html.push_str("    </style>\n");
        html.push_str("</head>\n<body>\n");
        html.push_str("    <h1>Claude Conversations Export</h1>\n");
        html.push_str(&format!("    <p>Exported: {}</p>\n", chrono::Local::now().format("%Y-%m-%d %H:%M:%S")));
        
        for id in ids {
            html.push_str(&format!("    <div class=\"conversation\">\n"));
            html.push_str(&format!("        <div class=\"header\"><h2>Conversation: {}</h2></div>\n", id));
            html.push_str("        <div class=\"content\">Content would be loaded here</div>\n");
            html.push_str("    </div>\n");
        }
        
        html.push_str("</body>\n</html>");
        
        let mut file = fs::File::create(path).await?;
        file.write_all(html.as_bytes()).await?;
        
        Ok(())
    }
    
    async fn export_pdf(&self, _ids: &[String], path: &Path) -> Result<()> {
        // PDF export would require a PDF library like printpdf or wkhtmltopdf
        // For now, create a placeholder
        let content = b"PDF export not yet implemented";
        let mut file = fs::File::create(path).await?;
        file.write_all(content).await?;
        
        Ok(())
    }
    
    async fn export_zip(&self, ids: &[String], path: &Path) -> Result<()> {
        use zip::write::FileOptions;
        use zip::ZipWriter;
        
        let file = std::fs::File::create(path)?;
        let mut zip = ZipWriter::new(file);
        
        let options = zip::write::FileOptions::<()>::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .unix_permissions(0o755);
        
        // Add metadata file
        zip.start_file("metadata.json", options)?;
        let metadata = serde_json::json!({
            "export_version": "1.0",
            "exported_at": chrono::Local::now().to_rfc3339(),
            "conversation_count": ids.len(),
        });
        zip.write_all(serde_json::to_string_pretty(&metadata)?.as_bytes())?;
        
        // Add each conversation as a separate file
        for (index, id) in ids.iter().enumerate() {
            zip.start_file(format!("conversation_{:04}.json", index + 1), options)?;
            let content = serde_json::json!({
                "id": id,
                "exported_at": chrono::Local::now().to_rfc3339(),
                // In production, include actual conversation data
            });
            zip.write_all(serde_json::to_string_pretty(&content)?.as_bytes())?;
        }
        
        zip.finish()?;
        
        Ok(())
    }
}