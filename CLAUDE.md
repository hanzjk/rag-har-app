# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project contains an Android mobile application for human activity recognition. It supports two modes: Human Activity Data Collection and Activity Recognition.

In Data Collection mode, when the user starts collection, the app extracts data from motion sensors and sends it continuously through a WebSocket connection as sensor streams until the user presses the stop button.

In Activity Recognition mode, the app sends sensor data in real time via the WebSocket connection and displays the predicted activity on the screen.
