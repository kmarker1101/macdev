use anyhow::Result;
use clap::{Parser, Subcommand};
use clap_complete::Shell;

#[derive(Parser)]
#[command(name = "macdev")]
#[command(about = "Project-isolated development environments using Homebrew")]
pub struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize a new macdev environment
    Init,
    
    /// Add packages to the environment
    Add {
        /// Package specifications (e.g., python@3.11 rust node)
        packages: Vec<String>,

        /// Make packages available system-wide (impure)
        #[arg(long)]
        impure: bool,
    },

    /// Remove packages from the environment
    Remove {
        /// Package names
        packages: Vec<String>,
    },
    
    /// Install all packages from manifest
    Install,
    
    /// Enter the isolated shell environment
    Shell,

    /// List packages in the environment
    List,

    /// Sync packages from manifest(s)
    Sync,

    /// Garbage collect unused packages
    Gc,

    /// Check if environment needs setup (exits 1 if install needed)
    Check {
        /// Suppress output
        #[arg(long)]
        quiet: bool,
    },

    /// Upgrade packages
    Upgrade {
        /// Package to upgrade (upgrades all if not specified)
        package: Option<String>,
    },

    /// Add a Homebrew tap
    Tap {
        /// Tap name (e.g., homebrew/cask)
        tap: String,
    },

    /// Remove a Homebrew tap
    Untap {
        /// Tap name (e.g., homebrew/cask)
        tap: String,
    },

    /// Generate shell completion script
    Completion {
        /// Shell to generate completions for
        shell: Shell,
    },
}

impl Cli {
    pub fn parse() -> Self {
        <Self as Parser>::parse()
    }
    
    pub fn run(self) -> Result<()> {
        match self.command {
            Commands::Init => crate::manifest::init(),
            Commands::Add { packages, impure } => {
                for package in &packages {
                    crate::environment::add(package, impure)?;
                }
                Ok(())
            }
            Commands::Remove { packages } => {
                for package in &packages {
                    crate::environment::remove(package)?;
                }
                Ok(())
            }
            Commands::Install => crate::environment::install(),
            Commands::Shell => crate::shell::enter(),
            Commands::List => crate::manifest::list(),
            Commands::Sync => crate::environment::sync(),
            Commands::Gc => crate::environment::gc(),
            Commands::Check { quiet } => crate::environment::check(quiet),
            Commands::Upgrade { package } => crate::environment::upgrade(package.as_deref()),
            Commands::Tap { tap } => crate::environment::tap(&tap),
            Commands::Untap { tap } => crate::environment::untap(&tap),
            Commands::Completion { shell } => {
                Self::generate_completion(shell);
                Ok(())
            }
        }
    }

    fn generate_completion(shell: Shell) {
        use clap::CommandFactory;
        use clap_complete::generate;
        use std::io;

        let mut cmd = Self::command();
        let bin_name = cmd.get_name().to_string();
        generate(shell, &mut cmd, bin_name, &mut io::stdout());
    }
}
