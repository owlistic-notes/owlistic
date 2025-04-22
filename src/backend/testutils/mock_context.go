package testutils

import(
	"net/http"
	"github.com/gin-gonic/gin"
)

func GetTestGinContext(w http.ResponseWriter, req *http.Request) *gin.Context {
    gin.SetMode(gin.TestMode)
    c, _ := gin.CreateTestContext(w)
    c.Request = req
    return c
}