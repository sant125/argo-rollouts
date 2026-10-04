// App boba pro lab de canary: responde em /, erra de propósito conforme
// ERROR_RATE, e expõe /metrics no formato do Prometheus. Sem dependência.
package main

import (
	"context"
	"fmt"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"
)

var (
	version   = env("VERSION", "v1")
	errorRate = parseRate(env("ERROR_RATE", "0"))

	mu sync.Mutex
	// começa com 200 e 500 zerados: a série existe desde o início,
	// e a taxa de erro dá 0 em vez de "sem dado"
	total = map[int]int{http.StatusOK: 0, http.StatusInternalServerError: 0}
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", app)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) }) // probe nunca erra
	mux.HandleFunc("/metrics", metrics)

	srv := &http.Server{Addr: ":8080", Handler: mux}
	go func() {
		log.Printf("versao=%s error_rate=%.2f ouvindo :8080", version, errorRate)
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	// SIGTERM: para de aceitar conexão nova e termina as que estão em andamento
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
	log.Print("desligado")
}

func app(w http.ResponseWriter, _ *http.Request) {
	code := http.StatusOK
	if rand.Float64() < errorRate {
		code = http.StatusInternalServerError
	}
	mu.Lock()
	total[code]++
	mu.Unlock()
	w.WriteHeader(code)
	fmt.Fprintf(w, "versao %s, codigo %d\n", version, code)
}

func metrics(w http.ResponseWriter, _ *http.Request) {
	mu.Lock()
	defer mu.Unlock()
	fmt.Fprintln(w, "# HELP http_requests_total Requisicoes em /, por codigo HTTP e versao.")
	fmt.Fprintln(w, "# TYPE http_requests_total counter")
	for code, n := range total {
		fmt.Fprintf(w, "http_requests_total{code=\"%d\",version=\"%s\"} %d\n", code, version, n)
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func parseRate(s string) float64 {
	f, err := strconv.ParseFloat(s, 64)
	if err != nil || f < 0 || f > 1 {
		log.Fatalf("ERROR_RATE precisa ser entre 0 e 1, veio %q", s)
	}
	return f
}
