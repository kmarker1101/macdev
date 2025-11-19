use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

const MANIFEST_FILE: &str = ".macdev/manifest.toml";

fn global_manifest_path() -> Result<PathBuf> {
    let home = dirs::home_dir().context("Could not find home directory")?;
    Ok(home.join(".config/macdev/manifest.toml"))
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct Manifest {
    #[serde(default)]
    pub packages: HashMap<String, String>,

    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub impure: HashMap<String, bool>,

    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub gc: HashMap<String, String>,
}

impl Manifest {
    /// Load manifest from current directory
    pub fn load() -> Result<Self> {
        let path = PathBuf::from(MANIFEST_FILE);
        
        if !path.exists() {
            anyhow::bail!(
                "No manifest found. Run 'macdev init' to create one."
            );
        }
        
        let contents = fs::read_to_string(&path)
            .context("Failed to read manifest")?;
        
        let manifest: Manifest = toml::from_str(&contents)
            .context("Failed to parse manifest")?;
        
        Ok(manifest)
    }

    /// Load global manifest from home directory
    pub fn load_global() -> Result<Self> {
        let path = global_manifest_path()?;

        if !path.exists() {
            return Ok(Self::default());
        }

        let contents = fs::read_to_string(&path)
            .context("Failed to read global manifest")?;

        let manifest: Manifest = toml::from_str(&contents)
            .context("Failed to parse global manifest")?;

        Ok(manifest)
    }

    /// Save as global manifest
    pub fn save_global(&self) -> Result<()> {
        let path = global_manifest_path()?;
        let dir = path.parent().context("Invalid global manifest path")?;
        fs::create_dir_all(dir)?;

        let contents = toml::to_string_pretty(self)
            .context("Failed to serialize global manifest")?;

        fs::write(&path, contents)
            .context("Failed to write global manifest")?;

        Ok(())
    }

    /// Get the global manifest path as a display string
    pub fn global_manifest_display_path() -> Result<String> {
        let path = global_manifest_path()?;
        Ok(path.display().to_string())
    }
    
    /// Save manifest to disk (local - only packages section)
    pub fn save(&self) -> Result<()> {
        let dir = Path::new(".macdev");
        fs::create_dir_all(dir)?;

        // For local manifest, only save packages section
        let local_only = Manifest {
            packages: self.packages.clone(),
            impure: HashMap::new(),
            gc: HashMap::new(),
        };

        let contents = toml::to_string_pretty(&local_only)
            .context("Failed to serialize manifest")?;

        fs::write(MANIFEST_FILE, contents)
            .context("Failed to write manifest")?;

        Ok(())
    }
    
    /// Add a pure package
    pub fn add_package(&mut self, name: String, version: String) {
        self.packages.insert(name, version);
    }
    
    /// Add an impure package
    pub fn add_impure(&mut self, name: String) {
        self.impure.insert(name, true);
    }
    
    /// Remove a package
    pub fn remove_package(&mut self, name: &str) {
        self.packages.remove(name);
        self.impure.remove(name);
    }
    
    /// Check if manifest exists
    pub fn exists() -> bool {
        Path::new(MANIFEST_FILE).exists()
    }
}

/// Initialize a new manifest
pub fn init() -> Result<()> {
    use colored::*;
    
    if Manifest::exists() {
        println!("{}", "Manifest already exists".yellow());
        return Ok(());
    }
    
    let manifest = Manifest::default();
    manifest.save()?;
    
    println!("{}", "✓ Initialized macdev environment".green());
    println!("  Created {}", MANIFEST_FILE.bright_black());
    
    Ok(())
}

/// List packages in manifest
pub fn list() -> Result<()> {
    use colored::*;

    let global_manifest = Manifest::load_global()?;

    let has_pure = !global_manifest.packages.is_empty();
    let has_impure = !global_manifest.impure.is_empty();

    if !has_pure && !has_impure {
        println!("{}", "No packages installed".yellow());
        return Ok(());
    }

    let path = Manifest::global_manifest_display_path().unwrap_or_else(|_| "global manifest".to_string());

    if !global_manifest.packages.is_empty() {
        println!("{}", format!("Pure packages (from {}):", path).green().bold());
        for (name, version) in &global_manifest.packages {
            println!("  {}@{}", name, version);
        }
    }

    if !global_manifest.impure.is_empty() {
        if has_pure {
            println!();
        }
        println!("{}", format!("Impure packages (from {}):", path).cyan().bold());
        for name in global_manifest.impure.keys() {
            println!("  {}", name);
        }
    }

    Ok(())
}
