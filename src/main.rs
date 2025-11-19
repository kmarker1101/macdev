mod cli;
mod manifest;
mod homebrew;
mod environment;
mod shell;

use anyhow::Result;

fn main() -> Result<()> {
    let cli = cli::Cli::parse();
    cli.run()
}
