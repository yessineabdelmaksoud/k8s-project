param(
    [string]$GiteaUser = "yessine.abdelmaksoud.03@gmail.com",
    [string]$GiteaPass = "vagrant123",
    [string]$RepoUrl = "http://192.168.56.20:3000/vagrant/infra.git"
)

$scriptPath = Join-Path $PSScriptRoot "bootstrap_repo.sh"
$scriptContent = Get-Content -Raw -Path $scriptPath
$scriptContent = $scriptContent -replace "`r`n", "`n"
$scriptContent = $scriptContent -replace "`r", ""

$env:GITEA_USER = $GiteaUser
$env:GITEA_PASS = $GiteaPass

$scriptContent | vagrant ssh services -c "GITEA_USER='$GiteaUser' GITEA_PASS='$GiteaPass' bash -s -- /home/vagrant /home/vagrant/infra-repo $RepoUrl"