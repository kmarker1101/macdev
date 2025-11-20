use anyhow::{Context, Result};
use std::path::PathBuf;
use std::process::Command;

/// Check if Homebrew is installed
pub fn is_installed() -> bool {
    Command::new("brew")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Check if a package is installed
pub fn is_package_installed(package: &str) -> Result<bool> {
    let output = Command::new("brew").args(["list", package]).output()?;

    Ok(output.status.success())
}

/// Install a package (with optional unlinking for isolation)
pub fn install_package(package: &str, link: bool) -> Result<()> {
    use colored::*;

    println!("  Installing {} via Homebrew...", package.cyan());

    let status = Command::new("brew")
        .args(["install", package])
        .status()
        .context("Failed to run 'brew install'")?;

    if !status.success() {
        anyhow::bail!("Failed to install {}", package);
    }

    // If we don't want it linked (pure package), unlink it
    if !link {
        let _ = unlink_package(package); // Unlink after install
    }

    Ok(())
}

/// Unlink a package (remove from global availability)
pub fn unlink_package(package: &str) -> Result<()> {
    let output = Command::new("brew")
        .args(["unlink", package])
        .output()
        .context("Failed to run 'brew unlink'")?;

    if !output.status.success() {
        anyhow::bail!("Failed to unlink {}", package);
    }

    // Only show output if symlinks were actually removed (not "0 symlinks removed")
    let stdout = String::from_utf8_lossy(&output.stdout);
    if !stdout.contains("0 symlinks removed") {
        print!("{}", stdout);
    }

    Ok(())
}

/// Get the installation path for a package
pub fn package_prefix(package: &str) -> Result<PathBuf> {
    let output = Command::new("brew")
        .args(["--prefix", package])
        .output()
        .context(format!("Failed to get prefix for {}", package))?;

    if !output.status.success() {
        anyhow::bail!("Package {} is not installed", package);
    }

    let prefix = String::from_utf8(output.stdout)?.trim().to_string();

    Ok(PathBuf::from(prefix))
}

/// Uninstall a package
pub fn uninstall_package(package: &str) -> Result<()> {
    let output = Command::new("brew")
        .args(["uninstall", package])
        .output()
        .context("Failed to run 'brew uninstall'")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("{}", stderr.trim());
    }

    Ok(())
}

/// Run brew cleanup
pub fn cleanup() -> Result<()> {
    let status = Command::new("brew")
        .arg("cleanup")
        .status()
        .context("Failed to run 'brew cleanup'")?;

    if !status.success() {
        anyhow::bail!("brew cleanup failed");
    }

    Ok(())
}

/// Ensure a package is installed (install if needed)
/// Returns the package prefix path
pub fn ensure_package(package: &str, link: bool) -> Result<PathBuf> {
    if !is_package_installed(package)? {
        install_package(package, link)?;
    } else if !link {
        // If package exists but we want it unlinked, unlink it
        let _ = unlink_package(package); // Ignore error if already unlinked
    }

    package_prefix(package)
}

/// Get list of dependencies for a package
pub fn package_deps(package: &str) -> Result<Vec<String>> {
    let output = Command::new("brew")
        .args(["deps", "--formula", package])
        .output()
        .context(format!("Failed to get dependencies for {}", package))?;

    if !output.status.success() {
        return Ok(Vec::new()); // No dependencies or package doesn't exist
    }

    let deps_output = String::from_utf8(output.stdout)?;
    let deps: Vec<String> = deps_output
        .lines()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    Ok(deps)
}

/// Check if a tap is already tapped
pub fn is_tap_tapped(tap: &str) -> Result<bool> {
    let output = Command::new("brew")
        .args(["tap"])
        .output()
        .context("Failed to run 'brew tap'")?;

    if !output.status.success() {
        return Ok(false);
    }

    let taps_output = String::from_utf8(output.stdout)?;
    Ok(taps_output.lines().any(|line| line.trim() == tap))
}

/// Add a tap
pub fn tap(tap_name: &str) -> Result<()> {
    use colored::*;

    println!("  Tapping {} via Homebrew...", tap_name.cyan());

    let status = Command::new("brew")
        .args(["tap", tap_name])
        .status()
        .context("Failed to run 'brew tap'")?;

    if !status.success() {
        anyhow::bail!("Failed to tap {}", tap_name);
    }

    Ok(())
}

/// Remove a tap
pub fn untap(tap_name: &str) -> Result<()> {
    use colored::*;

    println!("  Untapping {} via Homebrew...", tap_name.cyan());

    let status = Command::new("brew")
        .args(["untap", tap_name])
        .status()
        .context("Failed to run 'brew untap'")?;

    if !status.success() {
        anyhow::bail!("Failed to untap {}", tap_name);
    }

    Ok(())
}
