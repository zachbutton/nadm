package main

import (
	_ "embed"
	"os"
	"os/exec"
	"strings"
)

//go:embed core.sh
var script string

func main() {
	cmd := exec.Command("bash", "-c", script+"\nmain")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "NADM_ARGS="+strings.Join(os.Args[1:], " "))

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			os.Exit(exitErr.ExitCode())
		}
		os.Exit(1)
	}
}
