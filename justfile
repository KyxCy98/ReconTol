project := "main.sh"
script := "./lib/core/install.sh"

default:
    echo "Running script.."

install:
    chmod +x {{script}}
    ./{{script}}
