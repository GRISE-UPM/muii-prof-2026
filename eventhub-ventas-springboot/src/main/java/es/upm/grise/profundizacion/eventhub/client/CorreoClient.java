package es.upm.grise.profundizacion.eventhub.client;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class CorreoClient {

    private final RestClient restClient;

    public CorreoClient(ClientHttpRequestFactory requestFactory,
                        @Value("${servicios.correos.url}") String url) {
        this.restClient = RestClient.builder()
                .baseUrl(url)
                .requestFactory(requestFactory)
                .build();
    }

    public void enviarConfirmacionCompra(ConfirmacionCompraRequest peticion) {
        restClient.post()
                .uri("/api/correos/confirmacion-compra")
                .contentType(MediaType.APPLICATION_JSON)
                .body(peticion)
                .retrieve()
                .toBodilessEntity();
    }
}
