use anyhow::{Context, Result};
use colored::*;
use std::env;
use std::path::PathBuf;
use std::process::Command;

/// Enter the isolated shell environment
pub fn enter() -> Result<()> {
    // Only run install if not already in a macdev shell (avoid conflicts)
    if env::var("MACDEV_ACTIVE").is_err() {
        println!("{}", "Ensuring environment is up to date...".cyan());
        crate::environment::install()?;
        println!();
    }

    let profile_dir = PathBuf::from(".macdev/profile");

    // Build PATH with profile/bin at the front
    let profile_bin = profile_dir.join("bin").canonicalize()?;
    let current_path = env::var("PATH").unwrap_or_default();
    let new_path = format!("{}:{}", profile_bin.display(), current_path);

    // Get current shell
    let shell = env::var("SHELL").unwrap_or_else(|_| "/bin/bash".to_string());

    println!("{}", "Entering macdev environment...".cyan());
    println!("  Shell: {}", shell.bright_black());
    println!("  Type 'exit' to leave");
    println!();

    // Spawn shell with modified PATH
    let status = Command::new(&shell)
        .env("PATH", new_path)
        .env("MACDEV_ACTIVE", "1")
        .status()
        .context("Failed to spawn shell")?;

    if !status.success() {
        eprintln!("Shell exited with status: {:?}", status);
        anyhow::bail!("Shell exited with error");
    }

    Ok(())
}
